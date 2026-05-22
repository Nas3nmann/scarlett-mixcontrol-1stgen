import SwiftUI
import ScarlettCore

// Centralised palette to keep the Control-2-style dark look consistent.

enum Theme {
    /// Main window background (~#171717).
    static let background = Color(white: 0.09)

    /// Card / panel background — the strip / section surfaces (~#222).
    static let panel = Color(white: 0.14)

    /// Slightly lifted surface — used for hover / focused / selected (~#2c2c2c).
    static let panelRaised = Color(white: 0.18)

    /// Subtle divider line.
    static let divider = Color(white: 0.22)

    /// Primary text.
    static let textPrimary = Color(white: 0.95)

    /// Secondary / caption text.
    static let textSecondary = Color(white: 0.55)

    /// Channel underline for analog hardware inputs.
    static let accentAnalog = Color(red: 0.95, green: 0.35, blue: 0.30)

    /// Channel underline for DAW / playback / PCM.
    static let accentPlayback = Color(red: 0.30, green: 0.65, blue: 1.00)

    /// Channel underline for mix-bus loops and other.
    static let accentOther = Color(white: 0.40)

    /// Mute button when engaged (Control 2 uses blue, not red).
    static let muteActive = Color(red: 0.25, green: 0.50, blue: 0.95)

    /// Solo button when engaged.
    static let soloActive = Color(red: 0.95, green: 0.70, blue: 0.25)

    /// Fader knob highlight.
    static let faderKnob = Color(white: 0.78)
    static let faderKnobShadow = Color.black.opacity(0.5)
    static let faderTrack = Color(white: 0.06)
    static let faderTrackFill = Color(white: 0.32)

    /// Meter gradient stops.
    static let meterLow = Color(red: 0.30, green: 0.80, blue: 0.40)
    static let meterMid = Color(red: 0.95, green: 0.80, blue: 0.20)
    static let meterHigh = Color(red: 0.95, green: 0.30, blue: 0.25)
}

extension SignalSource {
    /// Color used for the strip's channel underline in the mixer.
    var accentColor: Color {
        switch self {
        case .daw1, .daw2, .daw3, .daw4, .daw5, .daw6,
             .pcm7, .pcm8, .pcm9, .pcm10, .pcm11, .pcm12:
            return Theme.accentPlayback
        case .analog1, .analog2, .analog3, .analog4,
             .spdif1, .spdif2:
            return Theme.accentAnalog
        case .off:
            return Theme.accentOther
        }
    }
}
