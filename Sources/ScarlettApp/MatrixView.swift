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
            Text("Pick a bus tab to set its per-channel gains. Use the strips' source pickers to wire signals in.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 320)
        }
    }

    private var busTabs: some View {
        HStack(spacing: 4) {
            ForEach(MixBus.matrixOutputs) { bus in
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
            actionButton(icon: "arrow.counterclockwise", label: "Clear peaks") {
                state.clearMaxPeaks()
            }
            .help("Reset the red max-peak tick on every strip.")

            actionButton(
                icon: state.masterMuted ? "speaker.slash.fill" : "speaker.wave.2",
                label: state.masterMuted ? "Master muted" : "Mute all",
                active: state.masterMuted,
                activeColor: Theme.muteActive
            ) {
                state.userSetMasterMute(!state.masterMuted)
            }
            .help("Mute every output bus on the device.")

            actionButton(icon: "arrow.uturn.backward.circle", label: "Default config") {
                state.userResetRoutingAndMatrix()
            }
            .disabled(!state.isConnected)
            .help("Reset routing and matrix to defaults: Monitor + Phones routed direct from DAW 1/2 (Mac audio audible), matrix cleared, pinned DAW return re-established.")

            actionButton(icon: "internaldrive", label: "Save to hardware") {
                state.saveToFlash()
            }
            .disabled(!state.isConnected)
            .help("Persist current settings to device flash so they survive a power cycle.")
        }
    }

    private func actionButton(
        icon: String, label: String,
        active: Bool = false, activeColor: Color = Theme.muteActive,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? activeColor : Theme.panelRaised)
            .foregroundStyle(active ? .white : Theme.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var strips: some View {
        HStack(alignment: .top, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleChannels, id: \.self) { ch in
                        ChannelStrip(channel: ch, state: state)
                    }
                }
                .padding(.vertical, 4)
            }
            PinnedDawStrip(state: state)
            PinnedMasterStrip(state: state)
        }
    }
}
