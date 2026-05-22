import Foundation

// Per-device configuration for the 1st-gen Scarlett family.  Each profile
// captures the byte mappings + physical layout that the original
// MixControl 1.10.6 binary's per-product IpSigTab/OpSigTab tables encode.
//
// Why a profile rather than per-device enums:
//   The 1st-gen Scarletts share the same control-transfer protocol family
//   (cmd, wValue, wIndex semantics, matrix-cell addressing) but each
//   model assigns *different bytes* to the same conceptual signal.  E.g.
//   Mix M1 is byte 0x14 on the 8i6, 0x18 on the 18i6/18i8.  Likewise
//   Analog 1 is 0x0c on the 8i6, 0x08 on the 18i6, 0x06 on the 18i8.
//
//   Hard-coding one device's bytes into an enum means we can't reuse the
//   protocol layer for a sibling model.  A profile lets the protocol
//   code stay generic and the model-specific bytes live in data.

// MARK: - Profile structures

public struct DeviceProfile: Sendable, Equatable {
    /// Two profiles are equal iff they describe the same device (same PID).
    /// We compare by productID rather than every field because that's the
    /// only thing that practically distinguishes one from another.
    public static func == (a: DeviceProfile, b: DeviceProfile) -> Bool {
        a.productID == b.productID
    }

    /// USB product ID (vendor is always 0x1235 Focusrite).
    public let productID: UInt16
    /// Internal MixControl identifier ("USB14Tracker" etc.) — handy for
    /// debugging and cross-referencing with the original binary.
    public let internalName: String
    /// Marketing name shown to users.
    public let displayName: String
    /// True for everything we've not personally validated on hardware.
    public let isExperimental: Bool

    // ---- Matrix mixer dimensions --------------------------------------
    /// Number of matrix input channels (rows).  18 on every model so far.
    public let matrixInputCount: Int
    /// Number of mix bus outputs (columns).  6 on 8i6 + 18i6, 8 on 18i8.
    public let mixBusCount: Int

    // ---- Sources (signals that can feed matrix channels OR outputs) ---
    /// The full set of signal sources the device knows about, with their
    /// device byte values + display names.  Used by SourceDescriptor pickers
    /// in the matrix UI and by MixBus pickers in the routing UI.
    public let sources: [SourceDescriptor]

    // ---- Physical outputs (routable destinations) ---------------------
    /// Per-device set of physical output destinations.  `wValue` is what
    /// the router accepts in `setRouteSource(wValue:from:)`.
    public let physicalOutputs: [PhysicalOutput]

    // ---- USB capture (DAW input) destinations -------------------------
    /// Number of USB capture channels (the destinations of `setCaptureRoute`).
    /// 8i6 has 6 + 2 loopback; 18i6/18i8 have 14 + 2 loopback.
    public let captureChannelCount: Int
    public let loopbackChannelCount: Int

    // ---- Hardware switches --------------------------------------------
    /// Channels (1-indexed in the UI) that have a Line/Inst impedance
    /// toggle.  Empty if the device has no impedance switches.
    public let impedanceChannels: [Int]
    /// Channels (1-indexed) that have a Hi/Lo gain switch.
    public let hiLoChannels: [Int]
    /// Whether the device has a Monitor Mono fold-down switch (currently
    /// disabled in the UI for all models pending an unsolved crash).
    public let hasMonitorMono: Bool
}

public struct SourceDescriptor: Sendable, Hashable, Identifiable {
    /// Wire byte sent to the device.
    public let byte: UInt8
    /// Display name (e.g. "Analog 1", "DAW 3", "Mix M1").
    public let displayName: String
    /// Category — drives grouping in pickers and whether the value can
    /// be the input of a matrix channel ("FromMix" sources feed back the
    /// matrix's own outputs and aren't usually picked).
    public let category: Category

    public var id: UInt8 { byte }

    public enum Category: Sendable, Hashable {
        case off
        case analog
        case digital     // S/PDIF, ADAT
        case daw         // USB host → device
        case mixOutput   // FromMix1..N — matrix output as input to something
    }
}

public struct PhysicalOutput: Sendable, Hashable, Identifiable {
    /// `wValue` for `setRouteSource` on this output.
    public let wValue: UInt16
    /// Friendly name for routing tab labels.
    public let displayName: String
    /// Belongs to which stereo pair.  Used to group "Monitor L+R" rows.
    public let pairLabel: String
    /// True for the left side of its stereo pair.
    public let isLeft: Bool

    public var id: UInt16 { wValue }
}

// MARK: - Profiles

extension DeviceProfile {

    /// All known profiles in this build.  Detection at connect time
    /// matches the device's USB PID against these.
    public static let all: [DeviceProfile] = [.scarlett8i6, .scarlett18i6, .scarlett18i8]

    /// Look up a profile by PID.  Returns nil for unknown devices.
    public static func forProductID(_ pid: UInt16) -> DeviceProfile? {
        all.first(where: { $0.productID == pid })
    }

    // ---- Scarlett 8i6 1st gen (USB14Tracker) — VERIFIED ---------------
    public static let scarlett8i6 = DeviceProfile(
        productID: 0x8002,
        internalName: "USB14Tracker",
        displayName: "Scarlett 8i6 (1st gen)",
        isExperimental: false,
        matrixInputCount: 18,
        mixBusCount: 6,
        sources: [
            .init(byte: 0xff, displayName: "Off",       category: .off),
            .init(byte: 0x0c, displayName: "Analog 1",  category: .analog),
            .init(byte: 0x0d, displayName: "Analog 2",  category: .analog),
            .init(byte: 0x0e, displayName: "Analog 3",  category: .analog),
            .init(byte: 0x0f, displayName: "Analog 4",  category: .analog),
            .init(byte: 0x12, displayName: "S/PDIF 1",  category: .digital),
            .init(byte: 0x13, displayName: "S/PDIF 2",  category: .digital),
            .init(byte: 0x00, displayName: "DAW 1",     category: .daw),
            .init(byte: 0x01, displayName: "DAW 2",     category: .daw),
            .init(byte: 0x02, displayName: "DAW 3",     category: .daw),
            .init(byte: 0x03, displayName: "DAW 4",     category: .daw),
            .init(byte: 0x04, displayName: "DAW 5",     category: .daw),
            .init(byte: 0x05, displayName: "DAW 6",     category: .daw),
            .init(byte: 0x14, displayName: "Mix M1",    category: .mixOutput),
            .init(byte: 0x15, displayName: "Mix M2",    category: .mixOutput),
            .init(byte: 0x16, displayName: "Mix M3",    category: .mixOutput),
            .init(byte: 0x17, displayName: "Mix M4",    category: .mixOutput),
            .init(byte: 0x18, displayName: "Mix M5",    category: .mixOutput),
            .init(byte: 0x19, displayName: "Mix M6",    category: .mixOutput),
        ],
        physicalOutputs: [
            .init(wValue: 0, displayName: "Monitor L",   pairLabel: "Monitor", isLeft: true),
            .init(wValue: 1, displayName: "Monitor R",   pairLabel: "Monitor", isLeft: false),
            .init(wValue: 2, displayName: "Phones L",    pairLabel: "Phones",  isLeft: true),
            .init(wValue: 3, displayName: "Phones R",    pairLabel: "Phones",  isLeft: false),
            .init(wValue: 4, displayName: "S/PDIF L",    pairLabel: "S/PDIF",  isLeft: true),
            .init(wValue: 5, displayName: "S/PDIF R",    pairLabel: "S/PDIF",  isLeft: false),
        ],
        captureChannelCount: 6,
        loopbackChannelCount: 2,
        impedanceChannels: [1, 2],
        hiLoChannels: [3, 4],
        hasMonitorMono: false   // hidden until the disconnect is solved
    )

    // ---- Scarlett 18i6 1st gen (USB26Tracker) — EXPERIMENTAL ----------
    //
    // 8 analog inputs, 2 S/PDIF, 8 ADAT, 6 DAW.  Matrix is 18 × 6.
    // Routing destinations: Monitor + Phones + S/PDIF (6 outputs).
    public static let scarlett18i6 = DeviceProfile(
        productID: 0x8004,
        internalName: "USB26Tracker",
        displayName: "Scarlett 18i6 (1st gen)",
        isExperimental: true,
        matrixInputCount: 18,
        mixBusCount: 6,
        sources: [
            .init(byte: 0xff, displayName: "Off",       category: .off),
            .init(byte: 0x06, displayName: "Analog 1",  category: .analog),
            .init(byte: 0x07, displayName: "Analog 2",  category: .analog),
            .init(byte: 0x08, displayName: "Analog 3",  category: .analog),
            .init(byte: 0x09, displayName: "Analog 4",  category: .analog),
            .init(byte: 0x0a, displayName: "Analog 5",  category: .analog),
            .init(byte: 0x0b, displayName: "Analog 6",  category: .analog),
            .init(byte: 0x0c, displayName: "Analog 7",  category: .analog),
            .init(byte: 0x0d, displayName: "Analog 8",  category: .analog),
            .init(byte: 0x0e, displayName: "S/PDIF 1",  category: .digital),
            .init(byte: 0x0f, displayName: "S/PDIF 2",  category: .digital),
            .init(byte: 0x10, displayName: "ADAT 1",    category: .digital),
            .init(byte: 0x11, displayName: "ADAT 2",    category: .digital),
            .init(byte: 0x12, displayName: "ADAT 3",    category: .digital),
            .init(byte: 0x13, displayName: "ADAT 4",    category: .digital),
            .init(byte: 0x14, displayName: "ADAT 5",    category: .digital),
            .init(byte: 0x15, displayName: "ADAT 6",    category: .digital),
            .init(byte: 0x16, displayName: "ADAT 7",    category: .digital),
            .init(byte: 0x17, displayName: "ADAT 8",    category: .digital),
            .init(byte: 0x00, displayName: "DAW 1",     category: .daw),
            .init(byte: 0x01, displayName: "DAW 2",     category: .daw),
            .init(byte: 0x02, displayName: "DAW 3",     category: .daw),
            .init(byte: 0x03, displayName: "DAW 4",     category: .daw),
            .init(byte: 0x04, displayName: "DAW 5",     category: .daw),
            .init(byte: 0x05, displayName: "DAW 6",     category: .daw),
            .init(byte: 0x18, displayName: "Mix M1",    category: .mixOutput),
            .init(byte: 0x19, displayName: "Mix M2",    category: .mixOutput),
            .init(byte: 0x1a, displayName: "Mix M3",    category: .mixOutput),
            .init(byte: 0x1b, displayName: "Mix M4",    category: .mixOutput),
            .init(byte: 0x1c, displayName: "Mix M5",    category: .mixOutput),
            .init(byte: 0x1d, displayName: "Mix M6",    category: .mixOutput),
        ],
        physicalOutputs: [
            .init(wValue: 0, displayName: "Monitor L",  pairLabel: "Monitor", isLeft: true),
            .init(wValue: 1, displayName: "Monitor R",  pairLabel: "Monitor", isLeft: false),
            .init(wValue: 2, displayName: "Phones L",   pairLabel: "Phones",  isLeft: true),
            .init(wValue: 3, displayName: "Phones R",   pairLabel: "Phones",  isLeft: false),
            .init(wValue: 4, displayName: "S/PDIF L",   pairLabel: "S/PDIF",  isLeft: true),
            .init(wValue: 5, displayName: "S/PDIF R",   pairLabel: "S/PDIF",  isLeft: false),
        ],
        captureChannelCount: 14,    // 14 ToHost slots in MixControl's OpSigTab
        loopbackChannelCount: 0,    // no Loop. entries in OpSigTab kind=3 list
        impedanceChannels: [1, 2],  // Inputs 1+2 are combo jacks (mic preamp)
        hiLoChannels: [],           // 18i6 has separate Hi-Z buttons on mics, not Hi/Lo
        hasMonitorMono: false
    )

    // ---- Scarlett 18i8 1st gen (USB24Tracker) — EXPERIMENTAL ----------
    //
    // 4 analog (+ 4 line) + 2 S/PDIF + 8 ADAT + 8 DAW.  Matrix is 18 × 8.
    // 8 routable physical outputs (Monitor + Phones + Line 5/6 + S/PDIF).
    public static let scarlett18i8 = DeviceProfile(
        productID: 0x8014,
        internalName: "USB24Tracker",
        displayName: "Scarlett 18i8 (1st gen)",
        isExperimental: true,
        matrixInputCount: 18,
        mixBusCount: 8,
        sources: [
            .init(byte: 0xff, displayName: "Off",       category: .off),
            .init(byte: 0x08, displayName: "Analog 1",  category: .analog),
            .init(byte: 0x09, displayName: "Analog 2",  category: .analog),
            .init(byte: 0x0a, displayName: "Analog 3",  category: .analog),
            .init(byte: 0x0b, displayName: "Analog 4",  category: .analog),
            .init(byte: 0x0e, displayName: "S/PDIF L",  category: .digital),
            .init(byte: 0x0f, displayName: "S/PDIF R",  category: .digital),
            .init(byte: 0x10, displayName: "ADAT 1",    category: .digital),
            .init(byte: 0x11, displayName: "ADAT 2",    category: .digital),
            .init(byte: 0x12, displayName: "ADAT 3",    category: .digital),
            .init(byte: 0x13, displayName: "ADAT 4",    category: .digital),
            .init(byte: 0x14, displayName: "ADAT 5",    category: .digital),
            .init(byte: 0x15, displayName: "ADAT 6",    category: .digital),
            .init(byte: 0x16, displayName: "ADAT 7",    category: .digital),
            .init(byte: 0x17, displayName: "ADAT 8",    category: .digital),
            .init(byte: 0x00, displayName: "DAW 1",     category: .daw),
            .init(byte: 0x01, displayName: "DAW 2",     category: .daw),
            .init(byte: 0x02, displayName: "DAW 3",     category: .daw),
            .init(byte: 0x03, displayName: "DAW 4",     category: .daw),
            .init(byte: 0x04, displayName: "DAW 5",     category: .daw),
            .init(byte: 0x05, displayName: "DAW 6",     category: .daw),
            .init(byte: 0x06, displayName: "DAW 7",     category: .daw),
            .init(byte: 0x07, displayName: "DAW 8",     category: .daw),
            .init(byte: 0x18, displayName: "Mix M1",    category: .mixOutput),
            .init(byte: 0x19, displayName: "Mix M2",    category: .mixOutput),
            .init(byte: 0x1a, displayName: "Mix M3",    category: .mixOutput),
            .init(byte: 0x1b, displayName: "Mix M4",    category: .mixOutput),
            .init(byte: 0x1c, displayName: "Mix M5",    category: .mixOutput),
            .init(byte: 0x1d, displayName: "Mix M6",    category: .mixOutput),
            .init(byte: 0x1e, displayName: "Mix M7",    category: .mixOutput),
            .init(byte: 0x1f, displayName: "Mix M8",    category: .mixOutput),
        ],
        physicalOutputs: [
            .init(wValue: 0, displayName: "Monitor L",   pairLabel: "Monitor",  isLeft: true),
            .init(wValue: 1, displayName: "Monitor R",   pairLabel: "Monitor",  isLeft: false),
            .init(wValue: 2, displayName: "Phones L",    pairLabel: "Phones",   isLeft: true),
            .init(wValue: 3, displayName: "Phones R",    pairLabel: "Phones",   isLeft: false),
            .init(wValue: 4, displayName: "Line Out 5",  pairLabel: "Line 5+6", isLeft: true),
            .init(wValue: 5, displayName: "Line Out 6",  pairLabel: "Line 5+6", isLeft: false),
            .init(wValue: 6, displayName: "S/PDIF L",    pairLabel: "S/PDIF",   isLeft: true),
            .init(wValue: 7, displayName: "S/PDIF R",    pairLabel: "S/PDIF",   isLeft: false),
        ],
        captureChannelCount: 14,
        loopbackChannelCount: 2,
        impedanceChannels: [1, 2],
        hiLoChannels: [],
        hasMonitorMono: false
    )
}

// MARK: - Convenience accessors

extension DeviceProfile {
    /// Look up a source by its wire byte (or fall back to Off).
    public func source(forByte byte: UInt8) -> SourceDescriptor {
        sources.first(where: { $0.byte == byte })
            ?? SourceDescriptor(byte: 0xff, displayName: "Off (0x\(String(byte, radix: 16)))", category: .off)
    }

    /// Sources that are valid inputs to a matrix-mixer channel — everything
    /// except other matrix outputs (which would create a feedback loop unless
    /// the user explicitly wants it).
    public var matrixChannelSources: [SourceDescriptor] {
        sources.filter { $0.category != .mixOutput }
    }

    /// All Mix M1..Mn entries in source order.  Used to populate router pickers.
    public var mixBusSources: [SourceDescriptor] {
        sources.filter { $0.category == .mixOutput }
    }
}
