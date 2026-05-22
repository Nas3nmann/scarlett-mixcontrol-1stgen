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
    /// Decayed peak-hold values per source. Updated on every poll: each value
    /// either keeps the new live reading (if higher) or decays the previous
    /// hold by `peakDecayDbPerSecond * elapsed`.
    var peaksHeld: PeakReading = .empty
    /// "All-time" peak per source — never decays automatically. Useful for
    /// gain staging: glance at the strip to see how loud each channel has
    /// peaked since you last cleared.  Reset via `clearMaxPeaks()`.
    var peaksMax: PeakReading = .empty
    var metersStale: Bool = false   // true if last poll failed
    @ObservationIgnored private let peakDecayDbPerSecond: Double = 6
    @ObservationIgnored private var syncPollAccumulator: TimeInterval = 0

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
    /// Per-cell gains kept around so we always know what's actually on the
    /// device — but the user-facing controls are `mixerLevels` + `mixerPans`,
    /// which produce these values via `cellGain(level:pan:isLeft:)`.
    var mixerGains: [[Double]] = Array(repeating: Array(repeating: 0, count: 6), count: 18)
    /// One fader value per channel per stereo bus pair (M1+M2, M3+M4, M5+M6).
    /// Range -60…+6 dB, default 0.
    var mixerLevels: [[Double]] = Array(repeating: Array(repeating: 0, count: 3), count: 18)
    /// One pan position per channel per stereo bus pair. -1 = full left,
    /// 0 = center (no attenuation either side), +1 = full right.
    var mixerPans:   [[Double]] = Array(repeating: Array(repeating: 0, count: 3), count: 18)
    var mixerMutes: [[Bool]]   = Array(repeating: Array(repeating: false, count: 6), count: 18)
    var mixerSolos: [[Bool]]   = Array(repeating: Array(repeating: false, count: 6), count: 18)
    /// User-set custom names per matrix channel. Empty string = use default "Ch N".
    var mixerNames: [String]   = Array(repeating: "", count: 18)
    /// Indices of the LEFT channel of each linked stereo pair.  Channels are
    /// grouped into fixed even/odd pairs: (0,1), (2,3), (4,5), …, (16,17).
    /// If `linkedPairs.contains(0)`, channels 0 and 1 are linked.
    var linkedPairs: Set<Int>  = []

    /// User-saved presets (full snapshots of routes + matrix + names + links).
    var presets: [ScarlettPreset] = []
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

    private static let routesKey  = "scarlett.routes.v1"
    private static let busTabKey  = "scarlett.selectedBus.v1"
    private static let matrixKey  = "scarlett.matrix.v1"
    private static let presetsKey = "scarlett.presets.v1"

    private struct PersistedMatrix: Codable {
        var gains: [[Double]]        // legacy per-cell gains (kept for backward compat)
        var levels: [[Double]]?      // new: per-channel-per-pair level
        var pans: [[Double]]?        // new: per-channel-per-pair pan
        var mutes: [[Bool]]
        var solos: [[Bool]]
        var names: [String]
        var linkedLefts: [Int]?
    }

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

        // Matrix state: names + mute/solo flags + intended gains.
        //
        // After refreshFromDevice, mixerGains already holds whatever the
        // hardware reports.  For cells that the user had MUTED last session
        // the device returns -128 (because we wrote that as the effective
        // value); the user's intended slider position lives only in our
        // saved snapshot.  We restore that intended value when the saved
        // mute flag says the cell was muted — so unmuting later restores
        // a meaningful gain.
        if let data = defaults.data(forKey: Self.matrixKey),
           let m = try? JSONDecoder().decode(PersistedMatrix.self, from: data) {
            if m.mutes.count == 18 && m.mutes.allSatisfy({ $0.count == 6 }) {
                mixerMutes = m.mutes
            }
            if m.solos.count == 18 && m.solos.allSatisfy({ $0.count == 6 }) {
                mixerSolos = m.solos
            }
            if m.names.count == 18 {
                mixerNames = m.names
            }
            if let lefts = m.linkedLefts {
                linkedPairs = Set(lefts)
            }
            if m.gains.count == 18 && m.gains.allSatisfy({ $0.count == 6 }) {
                for ch in 0..<18 {
                    for bus in 0..<6 {
                        let soloActive = (0..<18).contains { mixerSolos[$0][bus] }
                        let overridden = mixerMutes[ch][bus] || (soloActive && !mixerSolos[ch][bus])
                        if overridden {
                            mixerGains[ch][bus] = m.gains[ch][bus]
                        }
                    }
                }
            }

            // Prefer saved level/pan if available; the device-derived values
            // computed earlier may not perfectly round-trip through quantised
            // cell gains, so the saved version is the better source of truth.
            if let lvls = m.levels, lvls.count == 18, lvls.allSatisfy({ $0.count == 3 }) {
                mixerLevels = lvls
            }
            if let pns = m.pans, pns.count == 18, pns.allSatisfy({ $0.count == 3 }) {
                mixerPans = pns
            }

            // Make sure the device actually reflects our mute/solo state in
            // case it was power-cycled between sessions.
            if let _ = device {
                for ch in 0..<18 {
                    for bus in MixMatOut.allCases {
                        let idx = Int(bus.rawValue)
                        let soloActive = (0..<18).contains { mixerSolos[$0][idx] }
                        if mixerMutes[ch][idx] || (soloActive && !mixerSolos[ch][idx]) {
                            pushCellGain(channel: ch, bus: bus)
                        }
                    }
                }
            }
        }

        // Presets list
        if let data = defaults.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([ScarlettPreset].self, from: data) {
            presets = decoded
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

    private func saveMatrix() {
        let m = PersistedMatrix(
            gains: mixerGains,
            levels: mixerLevels,
            pans: mixerPans,
            mutes: mixerMutes, solos: mixerSolos,
            names: mixerNames, linkedLefts: Array(linkedPairs)
        )
        if let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: Self.matrixKey)
        }
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
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

        // Derive the level + pan model from whatever per-cell gains the
        // device just reported.  Done after refreshFromDevice so the level/
        // pan UI starts in sync with reality.
        for ch in 0..<18 {
            for pair in 0..<3 {
                let g_L = mixerGains[ch][pair * 2]
                let g_R = mixerGains[ch][pair * 2 + 1]
                let (level, pan) = Self.deriveLevelAndPan(left: g_L, right: g_R)
                mixerLevels[ch][pair] = level
                mixerPans[ch][pair] = pan
            }
        }
    }

    // MARK: - Meter polling

    func startMeterPolling() {
        Task { @MainActor [weak self] in
            var lastTick = Date()
            while !Task.isCancelled {
                guard let self, let dev = self.device else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                let now = Date()
                let elapsed = now.timeIntervalSince(lastTick)
                lastTick = now
                let decay = self.peakDecayDbPerSecond * elapsed

                do {
                    let p = try dev.readPeaks()
                    self.peaks = p
                    self.peaksHeld = PeakReading(
                        inputs: zip(p.inputs, self.peaksHeld.inputs).map { max($0.0, $0.1 - decay) },
                        daw:    zip(p.daw,    self.peaksHeld.daw   ).map { max($0.0, $0.1 - decay) },
                        mixer:  zip(p.mixer,  self.peaksHeld.mixer ).map { max($0.0, $0.1 - decay) }
                    )
                    self.peaksMax = PeakReading(
                        inputs: zip(p.inputs, self.peaksMax.inputs).map { max($0.0, $0.1) },
                        daw:    zip(p.daw,    self.peaksMax.daw   ).map { max($0.0, $0.1) },
                        mixer:  zip(p.mixer,  self.peaksMax.mixer ).map { max($0.0, $0.1) }
                    )
                    self.metersStale = false
                } catch {
                    self.metersStale = true
                }

                // Re-read sync status roughly every second so the indicator
                // catches clock drops without doing a USB transfer every tick.
                self.syncPollAccumulator += elapsed
                if self.syncPollAccumulator >= 1.0 {
                    self.syncPollAccumulator = 0
                    if let s = try? dev.getSyncLocked() {
                        self.syncLocked = s
                    }
                }

                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms → 20 Hz
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
    /// - Otherwise: derived from `mixerLevels` + `mixerPans` for the bus pair
    ///   this bus belongs to.
    func effectiveGain(channel: Int, busIdx: Int) -> Double {
        if mixerMutes[channel][busIdx] { return -128 }
        let soloActive = (0..<18).contains { mixerSolos[$0][busIdx] }
        if soloActive && !mixerSolos[channel][busIdx] { return -128 }
        let pair = busIdx / 2
        let isLeft = busIdx % 2 == 0
        return Self.cellGain(level: mixerLevels[channel][pair],
                             pan: mixerPans[channel][pair],
                             isLeft: isLeft)
    }

    // MARK: - Level + pan math

    /// Convert a (level, pan, side) triple into the per-cell gain that the
    /// device's matrix mixer will use.  "Amp-style" pan law: at center both
    /// sides get the full level; panning hard to one side reduces the other
    /// to -∞ without attenuating the chosen side.
    static func cellGain(level: Double, pan: Double, isLeft: Bool) -> Double {
        let clamped = max(-1, min(1, pan))
        let factor: Double = isLeft
            ? (clamped <= 0 ? 1.0 : 1.0 - clamped)
            : (clamped >= 0 ? 1.0 : 1.0 + clamped)
        if factor <= 0.0001 { return -128 }
        return level + 20 * log10(factor)
    }

    /// Inverse of `cellGain` — recover a (level, pan) pair from the device's
    /// current L and R cell gains.  Used to migrate the matrix on launch.
    static func deriveLevelAndPan(left: Double, right: Double) -> (level: Double, pan: Double) {
        let safeL = left.isFinite  ? max(-128, left)  : -128
        let safeR = right.isFinite ? max(-128, right) : -128
        if abs(safeL - safeR) < 0.5 {
            return (max(safeL, safeR), 0)
        }
        if safeL > safeR {
            let level = safeL
            // pan in [-1, 0]: gain_R = level + 20·log10(1 + pan)
            let pan = pow(10, (safeR - level) / 20) - 1
            return (level, max(-1, pan))
        } else {
            let level = safeR
            // pan in (0, 1]: gain_L = level + 20·log10(1 - pan)
            let pan = 1 - pow(10, (safeL - level) / 20)
            return (level, min(1, pan))
        }
    }

    static func pairIndex(of bus: MixMatOut) -> Int { Int(bus.rawValue) / 2 }
    static func isLeftSide(of bus: MixMatOut) -> Bool { bus.rawValue % 2 == 0 }

    func userSetMixerSource(channel: Int, source: SignalSource) {
        guard (0..<18).contains(channel) else { return }
        mixerSources[channel] = source
        guard let dev = device else { return }
        writeAsync { try? dev.setMixerSource(channel: channel, source: source) }
    }

    // MARK: - Stereo link

    /// Fixed even/odd partner index for a given channel.
    private static func leftOfPair(_ ch: Int) -> Int { ch - (ch % 2) }

    func isLinked(_ ch: Int) -> Bool {
        linkedPairs.contains(Self.leftOfPair(ch))
    }

    func linkedPartner(_ ch: Int) -> Int? {
        guard isLinked(ch) else { return nil }
        return ch % 2 == 0 ? ch + 1 : ch - 1
    }

    func userToggleLink(channel ch: Int) {
        let left = Self.leftOfPair(ch)
        if linkedPairs.contains(left) {
            linkedPairs.remove(left)
        } else {
            linkedPairs.insert(left)
        }
        saveMatrix()
    }

    /// Set the channel-level fader for one stereo bus pair. Pushes both cells
    /// (L and R) in that pair to the device.  If the channel is in a linked
    /// stereo pair, the partner's level for the same pair moves with it.
    func userSetMixerLevel(channel: Int, pair: Int, level: Double) {
        guard (0..<18).contains(channel), (0..<3).contains(pair) else { return }
        mixerLevels[channel][pair] = level
        pushBusPair(channel: channel, pair: pair)
        if let partner = linkedPartner(channel) {
            mixerLevels[partner][pair] = level
            pushBusPair(channel: partner, pair: pair)
        }
        saveMatrix()
    }

    /// Set the L↔R pan for one stereo bus pair on one channel. Snaps to
    /// center when within ±0.04.
    func userSetMixerPan(channel: Int, pair: Int, pan: Double) {
        guard (0..<18).contains(channel), (0..<3).contains(pair) else { return }
        let snapped = abs(pan) < 0.04 ? 0 : max(-1, min(1, pan))
        mixerPans[channel][pair] = snapped
        pushBusPair(channel: channel, pair: pair)
        saveMatrix()
    }

    private func pushBusPair(channel: Int, pair: Int) {
        guard let leftBus  = MixMatOut(rawValue: UInt8(pair * 2)),
              let rightBus = MixMatOut(rawValue: UInt8(pair * 2 + 1)) else { return }
        pushCellGain(channel: channel, bus: leftBus)
        pushCellGain(channel: channel, bus: rightBus)
    }

    func userSetChannelName(channel: Int, name: String) {
        guard (0..<18).contains(channel) else { return }
        mixerNames[channel] = name
        saveMatrix()
    }

    /// Reset the all-time max peaks for every source.
    func clearMaxPeaks() {
        peaksMax = .empty
    }

    /// Reset the all-time max peak for one signal source only — used when the
    /// user clicks the "Mx" readout on a single channel strip.
    func clearMaxPeak(forSource source: SignalSource) {
        switch source {
        case .analog1: peaksMax.inputs[0] = -.infinity
        case .analog2: peaksMax.inputs[1] = -.infinity
        case .analog3: peaksMax.inputs[2] = -.infinity
        case .analog4: peaksMax.inputs[3] = -.infinity
        case .spdif1:  peaksMax.inputs[8] = -.infinity
        case .spdif2:  peaksMax.inputs[9] = -.infinity
        case .daw1:    peaksMax.daw[0] = -.infinity
        case .daw2:    peaksMax.daw[1] = -.infinity
        case .daw3:    peaksMax.daw[2] = -.infinity
        case .daw4:    peaksMax.daw[3] = -.infinity
        case .daw5:    peaksMax.daw[4] = -.infinity
        case .daw6:    peaksMax.daw[5] = -.infinity
        default: break
        }
    }

    // MARK: - Presets

    func userSavePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let snapshot = ScarlettPreset(
            id: UUID(),
            name: trimmed,
            createdAt: Date(),
            routes: Dictionary(uniqueKeysWithValues:
                routes.map { ($0.key.rawValue, $0.value.rawValue) }),
            mixerSources: mixerSources.map { $0.rawValue },
            mixerGains: mixerGains,
            mixerMutes: mixerMutes,
            mixerSolos: mixerSolos,
            mixerNames: mixerNames,
            linkedLefts: Array(linkedPairs),
            selectedBus: selectedBus.rawValue
        )

        // Replace any preset with the same name; otherwise append.
        if let idx = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[idx] = snapshot
        } else {
            presets.append(snapshot)
        }
        savePresets()
    }

    func userLoadPreset(_ preset: ScarlettPreset) {
        guard let dev = device else { return }

        // Routes
        for (routeRaw, busRaw) in preset.routes {
            guard let route = Route(rawValue: routeRaw),
                  let bus = MixBus(rawValue: busRaw) else { continue }
            routes[route] = bus
            writeAsync { try? dev.setRouteSource(route, from: bus) }
        }
        saveRoutes()

        // Matrix sources
        if preset.mixerSources.count == 18 {
            for ch in 0..<18 {
                guard let src = SignalSource(rawValue: preset.mixerSources[ch]) else { continue }
                mixerSources[ch] = src
                writeAsync { try? dev.setMixerSource(channel: ch, source: src) }
            }
        }

        // Mutes / solos / gains / names / links — applied in that order so
        // pushCellGain sees correct mute/solo flags when computing effective gain.
        if preset.mixerMutes.count == 18 { mixerMutes = preset.mixerMutes }
        if preset.mixerSolos.count == 18 { mixerSolos = preset.mixerSolos }
        if preset.mixerGains.count == 18 { mixerGains = preset.mixerGains }
        if preset.mixerNames.count == 18 { mixerNames = preset.mixerNames }
        linkedPairs = Set(preset.linkedLefts)

        for ch in 0..<18 {
            for bus in MixMatOut.allCases {
                pushCellGain(channel: ch, bus: bus)
            }
        }

        if let bus = MixMatOut(rawValue: preset.selectedBus) {
            selectedBus = bus
        }

        saveMatrix()
    }

    func userDeletePreset(_ preset: ScarlettPreset) {
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func userToggleMixerMute(channel: Int, bus: MixMatOut) {
        guard (0..<18).contains(channel) else { return }
        let busIdx = Int(bus.rawValue)
        let newValue = !mixerMutes[channel][busIdx]
        mixerMutes[channel][busIdx] = newValue
        pushCellGain(channel: channel, bus: bus)
        if let partner = linkedPartner(channel) {
            mixerMutes[partner][busIdx] = newValue
            pushCellGain(channel: partner, bus: bus)
        }
        saveMatrix()
    }

    /// Solo affects every cell in the same bus column, so we push all 18.
    func userToggleMixerSolo(channel: Int, bus: MixMatOut) {
        guard (0..<18).contains(channel) else { return }
        let busIdx = Int(bus.rawValue)
        let newValue = !mixerSolos[channel][busIdx]
        mixerSolos[channel][busIdx] = newValue
        if let partner = linkedPartner(channel) {
            mixerSolos[partner][busIdx] = newValue
        }
        for ch in 0..<18 {
            pushCellGain(channel: ch, bus: bus)
        }
        saveMatrix()
    }

    private func pushCellGain(channel: Int, bus: MixMatOut) {
        guard let dev = device else { return }
        let db = effectiveGain(channel: channel, busIdx: Int(bus.rawValue))
        mixerGains[channel][Int(bus.rawValue)] = db
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
