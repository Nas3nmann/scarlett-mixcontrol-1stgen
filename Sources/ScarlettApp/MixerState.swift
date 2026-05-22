import Foundation
import Observation
import ScarlettCore

// View model holding the live device handle, the latest peak meter reading,
// and the user's current slider/toggle positions. Writes to the device are
// only sent when the user changes a value — the model never tries to
// "sync" itself to the hardware on launch (we have no GET for most state).

@MainActor
@Observable
final class MixerState {
    // MARK: - Connection
    var device: ScarlettDevice?
    var connectionError: String?
    var firmware: String = "—"
    var serial: String = "—"

    /// Serial queue used to push USB writes off the main actor.  USB control
    /// transfers are fast (microseconds) but synchronous, and SwiftUI sliders
    /// fire ~60 updates/sec while dragging — running those on main causes
    /// visible jank.  All writes go through `writeAsync`.
    @ObservationIgnored
    private let usbQueue = DispatchQueue(label: "scarlett.usb-writes", qos: .userInitiated)

    @ObservationIgnored
    private nonisolated(unsafe) var _writeError: String?

    nonisolated private func writeAsync(_ work: @escaping @Sendable () -> Void) {
        usbQueue.async(execute: work)
    }

    // MARK: - Meters
    var peaks: PeakReading = .empty
    var metersStale: Bool = false   // true if last poll failed

    // MARK: - User-controlled values (defaults to "no change")
    //
    // Attenuation sliders: -60...0 dB range, default 0 = no attenuation.
    // We start sliders at 0 dB but DO NOT push that value to the device on
    // launch (the user might be running at -20 dB right now and we'd boost
    // them). First `userDidChange*` call sends the value.
    var monitorAtten: Double = 0
    var phonesAtten: Double  = 0
    var masterMuted: Bool    = false

    // Input switches — defaults are conservative (line / lo). Not pushed on launch.
    var impedance1: Impedance = .line
    var impedance2: Impedance = .line
    var hi3: Bool = false   // false = lo, true = hi
    var hi4: Bool = false

    // Routing — default "Off" displayed, not pushed on launch.
    var routes: [Route: MixBus] = [
        .monitorLeft: .off, .monitorRight: .off,
        .phonesLeft:  .off, .phonesRight:  .off,
        .spdifLeft:   .off, .spdifRight:   .off,
    ]

    // Device config — default values shown, not pushed on launch.
    var clock: ClockSource = .internalClock
    var sampleRate: UInt32 = 48000
    var syncLocked: Bool = false

    // Dim: -20 dB attenuation overlay on monitor outputs. Stores the
    // pre-dim attenuation so we can restore it.
    var dimEnabled: Bool = false
    @ObservationIgnored private var preDimMonitorAtten: Double = 0

    // Per-side independent mutes (vs the global master mute).
    var monitorLMuted: Bool = false
    var monitorRMuted: Bool = false
    var phonesLMuted:  Bool = false
    var phonesRMuted:  Bool = false

    // Matrix mixer: 18 input channels × 6 mix buses (M1..M6).
    // mixerSources[ch] is the signal feeding matrix channel `ch`.
    // mixerGains[ch][bus] is the user-set gain in dB of channel `ch` going to bus
    // M(bus+1) — i.e., what the slider shows. Mute and solo override what we
    // actually send to the device without changing the slider's stored value.
    var mixerSources: [SignalSource] = Array(repeating: .off, count: 18)
    var mixerGains: [[Double]] = Array(repeating: Array(repeating: 0, count: 6), count: 18)
    var mixerMutes: [[Bool]]   = Array(repeating: Array(repeating: false, count: 6), count: 18)
    var mixerSolos: [[Bool]]   = Array(repeating: Array(repeating: false, count: 6), count: 18)
    var selectedBus: MixMatOut = .m1 {
        didSet { saveSelectedBus() }
    }

    init() {
        do {
            let dev = try ScarlettDevice()
            self.device = dev
            if let bcd = dev.firmwareBCD() {
                let hi = (bcd >> 8) & 0xff
                let lo = bcd & 0xff
                let major = (hi >> 4) * 10 + (hi & 0xf)
                let minor = (lo >> 4) * 10 + (lo & 0xf)
                self.firmware = String(format: "v%d.%02d", major, minor)
            }
            self.serial = dev.serialNumber() ?? "—"
            refreshFromDevice()
            loadPersistedState()
        } catch {
            self.connectionError = "\(error)"
        }
    }

    // MARK: - UserDefaults persistence
    //
    // We only persist the values that aren't reliably readable from the
    // device — namely the output routing (firmware bug: GETs return 00 00
    // regardless of what was SET, see memory: project-routing-get-unreliable)
    // and the user's last-selected matrix bus tab (small UX win).
    //
    // Everything else (gains, mutes, atten, clock, etc.) is reliably read on
    // launch via refreshFromDevice and doesn't need to be saved.

    private static let routesKey = "scarlett.routes.v1"
    private static let busTabKey = "scarlett.selectedBus.v1"

    private func loadPersistedState() {
        let defaults = UserDefaults.standard

        // Routes — re-push to device so it actually honors them.
        if let data = defaults.data(forKey: Self.routesKey),
           let dict = try? JSONDecoder().decode([UInt16: UInt8].self, from: data) {
            for (routeRaw, busRaw) in dict {
                guard let route = Route(rawValue: routeRaw),
                      let bus = MixBus(rawValue: busRaw) else { continue }
                routes[route] = bus
                if let dev = device {
                    writeAsync { try? dev.setRouteSource(route, from: bus) }
                }
            }
        }

        // Selected bus tab
        if let raw = defaults.object(forKey: Self.busTabKey) as? UInt8,
           let bus = MixMatOut(rawValue: raw) {
            selectedBus = bus
        }
    }

    private func saveRoutes() {
        let dict = Dictionary(uniqueKeysWithValues:
            routes.map { ($0.key.rawValue, $0.value.rawValue) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.routesKey)
        }
    }

    private func saveSelectedBus() {
        UserDefaults.standard.set(selectedBus.rawValue, forKey: Self.busTabKey)
    }

    /// Read all controls' current state from the device and update the
    /// view-model fields. Called on launch; can be called again to resync
    /// (e.g. after MixControl on Windows changed something out from under us).
    func refreshFromDevice() {
        guard let dev = device else { return }
        // Individual failures are swallowed — we keep the previously-stored
        // value for that field and continue. If everything fails the
        // connectionError will already have been raised by an earlier call.
        if let v = try? dev.getClockSource()              { clock = v }
        if let v = try? dev.getSampleRate()               { sampleRate = v }
        if let v = try? dev.getSyncLocked()               { syncLocked = v }
        if let v = try? dev.getImpedance(channel: 0)      { impedance1 = v }
        if let v = try? dev.getImpedance(channel: 1)      { impedance2 = v }
        if let v = try? dev.getHiLoGain(channel: 3)       { hi3 = v }
        if let v = try? dev.getHiLoGain(channel: 4)       { hi4 = v }
        if let v = try? dev.getMute(.master)              { masterMuted = v }
        if let v = try? dev.getMute(.monitorLeft)         { monitorLMuted = v }
        if let v = try? dev.getMute(.monitorRight)        { monitorRMuted = v }
        if let v = try? dev.getMute(.phonesLeft)          { phonesLMuted = v }
        if let v = try? dev.getMute(.phonesRight)         { phonesRMuted = v }
        // Use the average of L/R for the mono "Monitor" / "Phones" sliders.
        if let l = try? dev.getAttenuation(.monitorLeft),
           let r = try? dev.getAttenuation(.monitorRight) { monitorAtten = (l + r) / 2 }
        if let l = try? dev.getAttenuation(.phonesLeft),
           let r = try? dev.getAttenuation(.phonesRight)  { phonesAtten = (l + r) / 2 }
        // NOTE: routing GETs always return 00 00 on the 1st-gen 8i6 regardless
        // of what was last SET — the firmware accepts writes to wIndex=0x3300
        // but exposes no readable state. So we don't read them; the pickers
        // show "Off" until the user actively chooses something.

        // Matrix mixer DOES read back correctly. 18 source reads + 18*6 = 108
        // gain reads. Each is a single USB control transfer of microseconds,
        // so the whole batch costs a few ms.
        for ch in 0..<18 {
            if let v = try? dev.getMixerSource(channel: ch) {
                mixerSources[ch] = v
            }
            for bus in MixMatOut.allCases {
                if let v = try? dev.getMixerGain(channel: ch, bus: bus) {
                    mixerGains[ch][Int(bus.rawValue)] = v
                }
            }
        }
    }

    // MARK: - Meter polling

    func startMeterPolling() {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let dev = self.device else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                do {
                    let p = try dev.readPeaks()
                    self.peaks = p
                    self.metersStale = false
                } catch {
                    self.metersStale = true
                }
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms → 20Hz
            }
        }
    }

    // MARK: - User actions (every public mutator goes through here so we
    // can ignore programmatic updates and surface errors uniformly)

    func userSetMonitorAtten(_ db: Double) {
        monitorAtten = db
        guard let dev = device else { return }
        writeAsync {
            try? dev.setAttenuation(.monitorLeft,  db: db)
            try? dev.setAttenuation(.monitorRight, db: db)
        }
    }

    func userSetPhonesAtten(_ db: Double) {
        phonesAtten = db
        guard let dev = device else { return }
        writeAsync {
            try? dev.setAttenuation(.phonesLeft,  db: db)
            try? dev.setAttenuation(.phonesRight, db: db)
        }
    }

    func userSetMasterMute(_ muted: Bool) {
        masterMuted = muted
        guard let dev = device else { return }
        writeAsync { try? dev.setMute(.master, muted: muted) }
    }

    // MARK: - Input switches

    func userSetImpedance(channel: Int, mode: Impedance) {
        if channel == 1 { impedance1 = mode } else if channel == 2 { impedance2 = mode }
        guard let dev = device else { return }
        writeAsync { try? dev.setImpedance(channel: channel - 1, mode: mode) }
    }

    func userSetHiLo(channel: Int, hi: Bool) {
        if channel == 3 { hi3 = hi } else if channel == 4 { hi4 = hi }
        guard let dev = device else { return }
        writeAsync { try? dev.setHiLoGain(channel: channel, hi: hi) }
    }

    // MARK: - Routing

    func userSetRoute(_ route: Route, to source: MixBus) {
        routes[route] = source
        saveRoutes()
        guard let dev = device else { return }
        writeAsync { try? dev.setRouteSource(route, from: source) }
    }

    // MARK: - Device config

    func userSetClock(_ src: ClockSource) {
        clock = src
        guard let dev = device else { return }
        writeAsync { try? dev.setClockSource(src) }
    }

    func userSetSampleRate(_ hz: UInt32) {
        sampleRate = hz
        guard let dev = device else { return }
        writeAsync { try? dev.setSampleRate(hz) }
    }

    // MARK: - Matrix mixer

    /// Computes the gain we actually want the device to apply for a cell,
    /// taking mute and solo into account.
    /// - Mute: cell is silenced (-128 dB).
    /// - Solo in bus: any cell soloed in this bus → all non-soloed cells in
    ///   the same bus are silenced.
    func effectiveGain(channel: Int, busIdx: Int) -> Double {
        if mixerMutes[channel][busIdx] { return -128 }
        let soloActive = (0..<18).contains { mixerSolos[$0][busIdx] }
        if soloActive && !mixerSolos[channel][busIdx] { return -128 }
        return mixerGains[channel][busIdx]
    }

    func userSetMixerSource(channel: Int, source: SignalSource) {
        guard (0..<18).contains(channel) else { return }
        mixerSources[channel] = source
        guard let dev = device else { return }
        writeAsync { try? dev.setMixerSource(channel: channel, source: source) }
    }

    func userSetMixerGain(channel: Int, bus: MixMatOut, db: Double) {
        guard (0..<18).contains(channel) else { return }
        mixerGains[channel][Int(bus.rawValue)] = db
        pushCellGain(channel: channel, bus: bus)
    }

    func userToggleMixerMute(channel: Int, bus: MixMatOut) {
        guard (0..<18).contains(channel) else { return }
        mixerMutes[channel][Int(bus.rawValue)].toggle()
        pushCellGain(channel: channel, bus: bus)
    }

    /// Solo affects every cell in the same bus column, so we push all 18.
    func userToggleMixerSolo(channel: Int, bus: MixMatOut) {
        guard (0..<18).contains(channel) else { return }
        mixerSolos[channel][Int(bus.rawValue)].toggle()
        for ch in 0..<18 {
            pushCellGain(channel: ch, bus: bus)
        }
    }

    private func pushCellGain(channel: Int, bus: MixMatOut) {
        guard let dev = device else { return }
        let db = effectiveGain(channel: channel, busIdx: Int(bus.rawValue))
        writeAsync { try? dev.setMixerGain(channel: channel, bus: bus, db: db) }
    }

    // MARK: - Master section helpers

    func userToggleDim() {
        dimEnabled.toggle()
        guard let dev = device else { return }
        if dimEnabled {
            preDimMonitorAtten = monitorAtten
            let dimmed = max(-128, monitorAtten - 20)
            monitorAtten = dimmed
            writeAsync {
                try? dev.setAttenuation(.monitorLeft,  db: dimmed)
                try? dev.setAttenuation(.monitorRight, db: dimmed)
            }
        } else {
            let restore = preDimMonitorAtten
            monitorAtten = restore
            writeAsync {
                try? dev.setAttenuation(.monitorLeft,  db: restore)
                try? dev.setAttenuation(.monitorRight, db: restore)
            }
        }
    }

    func userSetSideMute(bus: SignalOut, muted: Bool) {
        switch bus {
        case .monitorLeft:  monitorLMuted = muted
        case .monitorRight: monitorRMuted = muted
        case .phonesLeft:   phonesLMuted  = muted
        case .phonesRight:  phonesRMuted  = muted
        default: return
        }
        guard let dev = device else { return }
        writeAsync { try? dev.setMute(bus, muted: muted) }
    }

    // MARK: - Save

    func saveToFlash() {
        guard let dev = device else { return }
        writeAsync { try? dev.saveSettingsToHardware() }
    }
}
