import Foundation

// Protocol constants and command functions for the Focusrite Scarlett 1st-gen
// family (8i6 / 18i6). Ported from x42's scarlettmixer.py
// (https://github.com/x42/scarlettmixer/blob/master/scarlettmixer.py).
//
// All commands target USB interface 0 (Audio Control) via endpoint 0.
// bmRequestType encoding handled by ScarlettDevice.controlOut/controlIn.

// MARK: - Enums

public enum Impedance: UInt8, CaseIterable, Identifiable {
    case line = 0, instrument = 1
    public var id: UInt8 { rawValue }
    public var displayName: String { self == .line ? "Line" : "Instrument" }
}

public enum ClockSource: UInt8, CaseIterable, Identifiable {
    case internalClock = 1, spdif = 2, adat = 3
    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .internalClock: return "Internal"
        case .spdif: return "S/PDIF"
        case .adat: return "ADAT"
        }
    }
}

/// Signal sources that can be connected to matrix-mixer inputs.
///
/// IMPORTANT: byte values here are for the **1st-gen Scarlett 8i6**, which
/// differ from x42's reverse-engineered 18i6 mapping. Per the Linux kernel
/// driver (`sound/usb/mixer_scarlett.c` s8i6_info, offsets={0,12,16,18,18}):
///   0x00..0x05 → DAW 1..6
///   0x06..0x0b → PCM 7..12 (firmware exposes 12 PCM slots; only 6 are wired)
///   0x0c..0x0f → Analog 1..4 (only 4 analog ins on the 8i6, not 8)
///   0x10..0x11 → S/PDIF 1..2
///   0xff       → Off
public enum SignalSource: UInt8, CaseIterable, Identifiable, Hashable {
    case off = 0xff
    case daw1 = 0x00, daw2 = 0x01, daw3 = 0x02, daw4 = 0x03, daw5 = 0x04, daw6 = 0x05
    case pcm7 = 0x06, pcm8 = 0x07, pcm9 = 0x08, pcm10 = 0x09, pcm11 = 0x0a, pcm12 = 0x0b
    case analog1 = 0x0c, analog2 = 0x0d, analog3 = 0x0e, analog4 = 0x0f
    case spdif1 = 0x10, spdif2 = 0x11

    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .off:     return "Off"
        case .daw1:    return "DAW 1"
        case .daw2:    return "DAW 2"
        case .daw3:    return "DAW 3"
        case .daw4:    return "DAW 4"
        case .daw5:    return "DAW 5"
        case .daw6:    return "DAW 6"
        case .pcm7:    return "PCM 7"
        case .pcm8:    return "PCM 8"
        case .pcm9:    return "PCM 9"
        case .pcm10:   return "PCM 10"
        case .pcm11:   return "PCM 11"
        case .pcm12:   return "PCM 12"
        case .analog1: return "Analog 1"
        case .analog2: return "Analog 2"
        case .analog3: return "Analog 3"
        case .analog4: return "Analog 4"
        case .spdif1:  return "S/PDIF 1"
        case .spdif2:  return "S/PDIF 2"
        }
    }

    /// Useful sources on a real 8i6 (drops the PCM 7-12 slots that aren't
    /// wired to USB streams, since picking one of those produces silence).
    public static let availableOn8i6: [SignalSource] = [
        .off,
        .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
        .analog1, .analog2, .analog3, .analog4,
        .spdif1, .spdif2,
    ]
}

/// Sources for the router — superset of SignalSource plus the 6 matrix-mixer outputs.
/// Same byte mapping as `SignalSource` (Linux's `s8i6_info` for both opt_master
/// and opt_matrix uses the same offsets table). Mix M1..M6 sit at 0x18..0x1d.
public enum MixBus: UInt8, CaseIterable, Identifiable, Hashable {
    case off = 0xff
    case daw1 = 0x00, daw2 = 0x01, daw3 = 0x02, daw4 = 0x03, daw5 = 0x04, daw6 = 0x05
    case pcm7 = 0x06, pcm8 = 0x07, pcm9 = 0x08, pcm10 = 0x09, pcm11 = 0x0a, pcm12 = 0x0b
    case analog1 = 0x0c, analog2 = 0x0d, analog3 = 0x0e, analog4 = 0x0f
    case spdif1 = 0x10, spdif2 = 0x11
    case m1 = 0x18, m2 = 0x19, m3 = 0x1a, m4 = 0x1b, m5 = 0x1c, m6 = 0x1d

    public var id: UInt8 { rawValue }
    public var displayName: String {
        switch self {
        case .off:     return "Off"
        case .daw1:    return "DAW 1"
        case .daw2:    return "DAW 2"
        case .daw3:    return "DAW 3"
        case .daw4:    return "DAW 4"
        case .daw5:    return "DAW 5"
        case .daw6:    return "DAW 6"
        case .pcm7:    return "PCM 7"
        case .pcm8:    return "PCM 8"
        case .pcm9:    return "PCM 9"
        case .pcm10:   return "PCM 10"
        case .pcm11:   return "PCM 11"
        case .pcm12:   return "PCM 12"
        case .analog1: return "Analog 1"
        case .analog2: return "Analog 2"
        case .analog3: return "Analog 3"
        case .analog4: return "Analog 4"
        case .spdif1:  return "S/PDIF 1"
        case .spdif2:  return "S/PDIF 2"
        case .m1:      return "Mix M1"
        case .m2:      return "Mix M2"
        case .m3:      return "Mix M3"
        case .m4:      return "Mix M4"
        case .m5:      return "Mix M5"
        case .m6:      return "Mix M6"
        }
    }

    /// Useful sources on a 1st-gen Scarlett 8i6.
    public static let availableOn8i6: [MixBus] = [
        .off,
        .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
        .analog1, .analog2, .analog3, .analog4,
        .spdif1, .spdif2,
        .m1, .m2, .m3, .m4, .m5, .m6,
    ]
}

/// Physical output route index (0..5).
public enum Route: UInt16, CaseIterable, Identifiable {
    case monitorLeft = 0, monitorRight = 1
    case phonesLeft = 2,  phonesRight = 3
    case spdifLeft  = 4,  spdifRight  = 5

    public var id: UInt16 { rawValue }
    public var displayName: String {
        switch self {
        case .monitorLeft:  return "Monitor L"
        case .monitorRight: return "Monitor R"
        case .phonesLeft:   return "Phones L"
        case .phonesRight:  return "Phones R"
        case .spdifLeft:    return "S/PDIF L"
        case .spdifRight:   return "S/PDIF R"
        }
    }
}

/// Post-routing gain stages (master + monitor L/R + phones L/R).
public enum SignalOut: UInt16 {
    case master = 0
    case monitorLeft = 1, monitorRight = 2
    case phonesLeft = 3,  phonesRight = 4
}

/// Matrix mixer output bus index (M1..M6).
public enum MixMatOut: UInt8, CaseIterable, Identifiable {
    case m1 = 0, m2 = 1, m3 = 2, m4 = 3, m5 = 4, m6 = 5
    public var id: UInt8 { rawValue }
    public var displayName: String { "M\(rawValue + 1)" }
}

// MARK: - Gain encoding (matches x42 byte-for-byte)

/// Bus attenuation: -∞ .. 0 dB → 2 bytes LE.
/// Clamps at -128 dB and 0 dB.
public func attenuationBytes(db: Double) -> [UInt8] {
    if db <= -128 { return [0x00, 0x80] }
    if db >= 0    { return [0x00, 0x00] }
    let raw = Int(floor(65536.5 + 256.0 * db))
    return [UInt8(raw & 0xff), UInt8((raw >> 8) & 0xff)]
}

/// Mixer-matrix per-cell gain: -128 .. +6 dB → 2 bytes LE.
public func gainBytes(db: Double) -> [UInt8] {
    var v = Int(floor(db + 0.5))
    if v <= -128 { return [0x00, 0x80] }
    if v > 6     { return [0x00, 0x06] }
    if v >= 0    { return [0x00, UInt8(v)] }
    // negative: two's-complement-ish in the high byte
    v = 0x100 + v
    return [0x00, UInt8(v)]
}

let muteBytes:   [UInt8] = [0x01, 0x00]
let unmuteBytes: [UInt8] = [0x00, 0x00]

// MARK: - Peak readings

public struct PeakReading {
    public var inputs: [Double]   // 18 values (only first 8 meaningful on 8i6)
    public var daw: [Double]      // 6 values
    public var mixer: [Double]    // 8 values

    public init(inputs: [Double], daw: [Double], mixer: [Double]) {
        self.inputs = inputs
        self.daw = daw
        self.mixer = mixer
    }

    public static let empty = PeakReading(
        inputs: Array(repeating: -.infinity, count: 18),
        daw:    Array(repeating: -.infinity, count: 6),
        mixer:  Array(repeating: -.infinity, count: 8)
    )
}

// MARK: - Commands

extension ScarlettDevice {

    // ---- Switches ---------------------------------------------------------

    /// Set line/instrument impedance for channels 0 or 1 (the combo inputs).
    public func setImpedance(channel: Int, mode: Impedance) throws {
        guard (0...1).contains(channel) else { throw ScarlettError.invalidArgument("channel must be 0 or 1") }
        try controlOut(
            cmd: 0x01,
            value: 0x0901 + UInt16(channel),
            index: 0x0100,
            data: [mode.rawValue, 0x00]
        )
    }

    /// 8i6-specific: hi/lo gain switch for analog inputs 3 and 4.
    /// Channel 3 → wValue 0x0803, channel 4 → wValue 0x0804. (x42 sets [0,0] for "lo".)
    public func setHiLoGain(channel: Int, hi: Bool) throws {
        guard (3...4).contains(channel) else { throw ScarlettError.invalidArgument("hi/lo channel must be 3 or 4") }
        try controlOut(
            cmd: 0x01,
            value: 0x0800 + UInt16(channel),
            index: 0x0100,
            data: [hi ? 0x01 : 0x00, 0x00]
        )
    }

    /// Set device clock source.
    public func setClockSource(_ src: ClockSource) throws {
        try controlOut(cmd: 0x01, value: 0x0100, index: 0x2800, data: [src.rawValue])
    }

    /// Set sample rate in Hz (44100, 48000, 88200, 96000).
    /// CAUTION: changing rate while audio is streaming will glitch usbaudiod.
    public func setSampleRate(_ hz: UInt32) throws {
        let bytes: [UInt8] = [
            UInt8(hz & 0xff),
            UInt8((hz >> 8) & 0xff),
            UInt8((hz >> 16) & 0xff),
            UInt8((hz >> 24) & 0xff),
        ]
        try controlOut(cmd: 0x01, value: 0x0100, index: 0x2900, data: bytes)
    }

    // ---- Bus mute / attenuation -------------------------------------------

    /// Mute/unmute a post-routing bus (master, mon L/R, ph L/R).
    public func setMute(_ bus: SignalOut, muted: Bool) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + bus.rawValue,
            index: 0x0a00,
            data: muted ? muteBytes : unmuteBytes
        )
    }

    /// Attenuate a post-routing bus (-∞ .. 0 dB).
    public func setAttenuation(_ bus: SignalOut, db: Double) throws {
        try controlOut(
            cmd: 0x01,
            value: 0x0200 + bus.rawValue,
            index: 0x0a00,
            data: attenuationBytes(db: db)
        )
    }

    // ---- Matrix mixer -----------------------------------------------------

    /// Connect a signal source to a matrix-mixer input channel (0..17).
    /// Per x42: if a source is already wired to another channel, the device
    /// won't double-assign it — disconnect first with `.off` if needed.
    public func setMixerSource(channel: Int, source: SignalSource) throws {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        try controlOut(
            cmd: 0x01,
            value: 0x0600 + UInt16(channel),
            index: 0x3200,
            data: [source.rawValue, 0x00]
        )
    }

    /// Set matrix-mixer per-cell gain (channel × bus). -128 .. +6 dB.
    public func setMixerGain(channel: Int, bus: MixMatOut, db: Double) throws {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        let mtx = UInt16(channel << 3) + UInt16(bus.rawValue & 0x07)
        try controlOut(
            cmd: 0x01,
            value: 0x0100 + mtx,
            index: 0x3c00,
            data: gainBytes(db: db)
        )
    }

    // ---- Router -----------------------------------------------------------

    /// Connect a source to one of the 6 physical output routes.
    public func setRouteSource(_ route: Route, from source: MixBus) throws {
        try controlOut(
            cmd: 0x01,
            value: route.rawValue,
            index: 0x3300,
            data: [source.rawValue, 0x00]
        )
    }

    // ---- Reads (GET_CUR) --------------------------------------------------
    //
    // The 1st-gen 8i6 is USB Audio Class 2.0 (bInterfaceProtocol = 0x20 in
    // the descriptor), so reads use bRequest = UAC2_CS_CUR = 0x01 (same as
    // writes) with bmRequestType = 0xa1 to indicate IN direction. The wValue
    // and wIndex are the same values used to set the control; response
    // length matches the set payload.

    public func getRouteSource(_ route: Route) throws -> MixBus {
        let r = try controlIn(cmd: 0x01, value: route.rawValue, index: 0x3300, length: 2)
        return MixBus(rawValue: r[0]) ?? .off
    }

    public func getMute(_ bus: SignalOut) throws -> Bool {
        let r = try controlIn(cmd: 0x01, value: 0x0100 + bus.rawValue, index: 0x0a00, length: 2)
        return r[0] != 0
    }

    public func getAttenuation(_ bus: SignalOut) throws -> Double {
        let r = try controlIn(cmd: 0x01, value: 0x0200 + bus.rawValue, index: 0x0a00, length: 2)
        let raw = UInt16(r[0]) | (UInt16(r[1]) << 8)
        // Decoder is the inverse of `attenuationBytes`: signed Int16 / 256.
        // [0x00, 0x00] → 0 dB; [0x00, 0xff] → -1 dB; [0x00, 0x80] → -128 dB.
        return Double(Int16(bitPattern: raw)) / 256.0
    }

    public func getImpedance(channel: Int) throws -> Impedance {
        guard (0...1).contains(channel) else { throw ScarlettError.invalidArgument("channel must be 0 or 1") }
        let r = try controlIn(cmd: 0x01, value: 0x0901 + UInt16(channel), index: 0x0100, length: 2)
        return r[0] == 1 ? .instrument : .line
    }

    public func getHiLoGain(channel: Int) throws -> Bool {
        guard (3...4).contains(channel) else { throw ScarlettError.invalidArgument("hi/lo channel must be 3 or 4") }
        let r = try controlIn(cmd: 0x01, value: 0x0800 + UInt16(channel), index: 0x0100, length: 2)
        return r[0] != 0
    }

    public func getClockSource() throws -> ClockSource {
        let r = try controlIn(cmd: 0x01, value: 0x0100, index: 0x2800, length: 1)
        return ClockSource(rawValue: r[0]) ?? .internalClock
    }

    public func getSampleRate() throws -> UInt32 {
        let r = try controlIn(cmd: 0x01, value: 0x0100, index: 0x2900, length: 4)
        return UInt32(r[0]) | (UInt32(r[1]) << 8) | (UInt32(r[2]) << 16) | (UInt32(r[3]) << 24)
    }

    public func getMixerSource(channel: Int) throws -> SignalSource {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        let r = try controlIn(cmd: 0x01, value: 0x0600 + UInt16(channel), index: 0x3200, length: 2)
        return SignalSource(rawValue: r[0]) ?? .off
    }

    /// Read clock-sync status: true = device is locked to its current clock source,
    /// false = no lock (audio will glitch/silence). Per Linux driver comments at
    /// `wIndex=0x3c00, wValue=0x0002, len=1` returning 1 byte (1 = locked).
    public func getSyncLocked() throws -> Bool {
        let r = try controlIn(cmd: 0x01, value: 0x0002, index: 0x3c00, length: 1)
        return r.first == 0x01
    }

    public func getMixerGain(channel: Int, bus: MixMatOut) throws -> Double {
        guard (0...17).contains(channel) else { throw ScarlettError.invalidArgument("mixer channel must be 0..17") }
        let mtx = UInt16(channel << 3) + UInt16(bus.rawValue & 0x07)
        let r = try controlIn(cmd: 0x01, value: 0x0100 + mtx, index: 0x3c00, length: 2)
        // gainBytes packs the dB value as a signed Int8 in the high byte.
        return Double(Int8(bitPattern: r[1]))
    }

    // ---- Save -------------------------------------------------------------

    /// Persist current mixer/routing state to the device's flash so it
    /// survives a power cycle. Writes to flash — don't call casually.
    public func saveSettingsToHardware() throws {
        try controlOut(cmd: 0x03, value: 0x005a, index: 0x3c00, data: [0xa5])
    }

    // ---- Peak meters ------------------------------------------------------

    public func readPeaks() throws -> PeakReading {
        let ins = try controlIn(cmd: 0x03, value: 0x0000, index: 0x3c00, length: 36)
        let daw = try controlIn(cmd: 0x03, value: 0x0003, index: 0x3c00, length: 12)
        let mix = try controlIn(cmd: 0x03, value: 0x0001, index: 0x3c00, length: 16)
        return PeakReading(
            inputs: decodePeaks(ins, count: 18),
            daw:    decodePeaks(daw, count: 6),
            mixer:  decodePeaks(mix, count: 8)
        )
    }
}

func val16ToDb(_ v: UInt16) -> Double {
    guard v > 0 else { return -.infinity }
    return 20.0 * log10(Double(v) / 65536.0)
}

func decodePeaks(_ bytes: [UInt8], count: Int) -> [Double] {
    (0..<count).map { i in
        let lo = UInt16(bytes[2*i])
        let hi = UInt16(bytes[2*i + 1])
        return val16ToDb((hi << 8) | lo)
    }
}
