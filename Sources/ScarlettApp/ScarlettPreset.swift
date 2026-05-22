import Foundation
import ScarlettCore

/// A complete snapshot of every user-controllable bit of state — exactly the
/// stuff a person would want to recall as "my podcast setup" or "tracking
/// drums today".  Stored in UserDefaults; could later be exported as a file.
public struct ScarlettPreset: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date

    /// Output routing: route raw value → MixBus raw value.
    public var routes: [UInt16: UInt8]

    /// Matrix mixer state (parallel to MixerState fields).
    public var mixerSources: [UInt8]    // SignalSource raw, 18 entries
    public var mixerGains:   [[Double]] // 18 × 6
    public var mixerMutes:   [[Bool]]   // 18 × 6
    public var mixerSolos:   [[Bool]]   // 18 × 6
    public var mixerNames:   [String]   // 18

    /// Left-channel indices of linked stereo pairs.
    public var linkedLefts: [Int]

    /// Bus that was active when the snapshot was taken.
    public var selectedBus: UInt8
}
