import SwiftUI
import ScarlettCore

/// The matrix mixer view — Control 2 style.
///
/// Top bar: bus tabs (Mix M1..M6).
/// Below: horizontally scrolling row of `ChannelStrip`s, one per matrix
/// channel that we expose to the user (first 14 of the 18 protocol slots —
/// the rest aren't useful on the 8i6).
struct MatrixMixerView: View {
    @Bindable var state: MixerState
    private let visibleChannels = 0..<14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            busTabs
            strips
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mixer").font(.title3).bold().foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Each row = one matrix input. Pick a bus tab to set its gain to that bus.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private var busTabs: some View {
        HStack(spacing: 4) {
            ForEach(MixMatOut.allCases) { bus in
                let selected = state.selectedBus == bus
                Button {
                    state.selectedBus = bus
                } label: {
                    Text(bus.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 60, height: 28)
                        .background(selected ? Theme.muteActive : Theme.panelRaised)
                        .foregroundStyle(selected ? .white : Theme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                state.clearMaxPeaks()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Clear peaks")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.panelRaised)
                .foregroundStyle(Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Reset the red max-peak tick on every strip.")
            Text("Showing gains for: \(state.selectedBus.displayName)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var strips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleChannels, id: \.self) { ch in
                    ChannelStrip(channel: ch, state: state)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
