import SwiftUI

/// Vertical fader inspired by Focusrite Control 2's mixer strips.
///
/// Linear scale across `-60...+6` dB to match Control 2's visible range.
/// Drag anywhere along the column (or on the knob) to set the value.
/// We never write more than 200 Hz from the gesture path — SwiftUI itself
/// throttles drag events. The slot for the dB scale is rendered separately
/// by `DbScale`, so the same coordinate math drives both.
struct VerticalFader: View {
    @Binding var db: Double
    var height: CGFloat = 220

    static let dbMin: Double = -60
    static let dbMax: Double = 6

    private let trackWidth: CGFloat = 4
    private let knobWidth: CGFloat = 30
    private let knobHeight: CGFloat = 14

    private var fillFraction: Double {
        let clamped = max(Self.dbMin, min(Self.dbMax, db))
        return (clamped - Self.dbMin) / (Self.dbMax - Self.dbMin)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let usable = h - knobHeight
            let knobOffsetY = usable * (1 - fillFraction)

            ZStack(alignment: .top) {
                // Track (full column)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.faderTrack)
                    .frame(width: trackWidth, height: h)
                    .frame(maxWidth: .infinity)

                // Filled portion (from knob center to bottom)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.faderTrackFill)
                    .frame(width: trackWidth, height: max(0, h - knobOffsetY - knobHeight / 2))
                    .frame(maxWidth: .infinity)
                    .offset(y: knobOffsetY + knobHeight / 2)

                // Knob
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.85), Theme.faderKnob, Color(white: 0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        Rectangle()
                            .fill(Color.black.opacity(0.35))
                            .frame(height: 1)
                    )
                    .frame(width: knobWidth, height: knobHeight)
                    .shadow(color: Theme.faderKnobShadow, radius: 1.5, y: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: knobOffsetY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = max(0, min(usable, drag.location.y - knobHeight / 2))
                        let frac = 1.0 - Double(y / usable)
                        db = Self.dbMin + frac * (Self.dbMax - Self.dbMin)
                    }
            )
        }
        .frame(width: knobWidth + 6, height: height)
    }
}

/// Static dB-scale tick column rendered beside the fader.
struct DbScale: View {
    var height: CGFloat = 220
    private let marks: [Int] = [0, -6, -12, -18, -24, -30, -36, -48, -60]
    private let dbMin: Double = VerticalFader.dbMin
    private let dbMax: Double = VerticalFader.dbMax

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.height - 14   // matches fader's `knobHeight`
            let knobHalf: CGFloat = 7
            ForEach(marks, id: \.self) { db in
                let frac = (Double(db) - dbMin) / (dbMax - dbMin)
                let y = knobHalf + usable * (1 - frac)
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(Theme.textSecondary.opacity(0.65))
                        .frame(width: 3, height: 1)
                    Text("\(db)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .position(x: 16, y: y)
            }
        }
        .frame(width: 28, height: height)
    }
}

/// Vertical peak meter rendered alongside a fader.
///
/// The thick gradient bar follows the live `db` value.  Two horizontal ticks
/// hover above it:
///  * `peakDb` (white): recent peak-hold value, decays at the rate set in
///    `MixerState.peakDecayDbPerSecond`.
///  * `maxPeakDb` (red): all-time max since the last "Clear peaks" — useful
///    for gain staging over a long take.
struct VerticalMeter: View {
    var db: Double
    var peakDb: Double = -.infinity
    var maxPeakDb: Double = -.infinity
    var height: CGFloat = 220
    private let dbMin: Double = -60
    private let dbMax: Double = 0
    private let width: CGFloat = 6

    private func fraction(_ v: Double) -> Double {
        let value = v.isFinite ? v : dbMin
        let clamped = max(dbMin, min(dbMax, value))
        return (clamped - dbMin) / (dbMax - dbMin)
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let currentFill = h * fraction(db)
            let peakOffset = h * (1 - fraction(peakDb))
            let maxOffset  = h * (1 - fraction(maxPeakDb))

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.faderTrack)
                    .frame(width: width, height: h)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.meterHigh, Theme.meterMid, Theme.meterLow],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: width, height: max(0, currentFill))

                // Recent peak-hold tick (white, decays).
                if peakDb.isFinite && peakDb > dbMin {
                    Rectangle()
                        .fill(Theme.textPrimary)
                        .frame(width: width + 2, height: 1.5)
                        .position(x: (width + 2) / 2, y: peakOffset)
                }

                // All-time max tick (red, persistent until cleared).
                if maxPeakDb.isFinite && maxPeakDb > dbMin {
                    Rectangle()
                        .fill(Theme.meterHigh)
                        .frame(width: width + 4, height: 1.5)
                        .position(x: (width + 2) / 2, y: maxOffset)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width + 4, height: height)
    }
}
