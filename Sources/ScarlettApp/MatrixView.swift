import SwiftUI
import ScarlettCore

struct MatrixMixerView: View {
    @Bindable var state: MixerState

    // Only show the first 14 matrix channels. The protocol has 18 but the
    // 8i6 doesn't have ADAT, so channels 14..17 aren't useful.
    private let visibleChannels = 0..<14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            busPicker
            channelList
            Text("Each row routes one signal into the selected mix bus (M1–M6). The bus output can then be assigned to a physical jack in the Output routing section above.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Matrix mixer").font(.headline)
            Spacer()
            Text("Mix bus output: \(state.selectedBus.displayName)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var busPicker: some View {
        Picker("Bus", selection: Binding(
            get: { state.selectedBus },
            set: { state.selectedBus = $0 }
        )) {
            ForEach(MixMatOut.allCases) { bus in
                Text(bus.displayName).tag(bus)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var channelList: some View {
        VStack(spacing: 4) {
            ForEach(visibleChannels, id: \.self) { ch in
                channelRow(channel: ch)
            }
        }
    }

    private func channelRow(channel ch: Int) -> some View {
        let bus = state.selectedBus
        let busIdx = Int(bus.rawValue)
        let db = state.mixerGains[ch][busIdx]
        let isMuted = state.mixerMutes[ch][busIdx]
        let isSoloed = state.mixerSolos[ch][busIdx]

        return HStack(spacing: 10) {
            Text("Ch \(ch + 1)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 38, alignment: .leading)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { state.mixerSources[ch] },
                set: { state.userSetMixerSource(channel: ch, source: $0) }
            )) {
                // Limit to sources that physically exist on the 8i6 (4 analog,
                // 2 S/PDIF, 6 DAW, Off). Bytes from the device that don't map
                // to one of these (e.g. PCM 7-12 slot residue, byte 0x12+)
                // decode to .off in MixerState, which displays cleanly here.
                ForEach(SignalSource.availableOn8i6) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)

            MuteSoloButton(letter: "M", isActive: isMuted, activeColor: .red) {
                state.userToggleMixerMute(channel: ch, bus: bus)
            }
            MuteSoloButton(letter: "S", isActive: isSoloed, activeColor: .orange) {
                state.userToggleMixerSolo(channel: ch, bus: bus)
            }

            Slider(
                value: Binding(
                    get: { db },
                    set: { state.userSetMixerGain(channel: ch, bus: bus, db: $0) }
                ),
                in: -128...6,
                step: 1
            )
            .controlSize(.small)
            .opacity(isMuted ? 0.4 : 1.0)

            Text(formatDb(db))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(isMuted ? .red : .secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatDb(_ db: Double) -> String {
        if db <= -128 { return "-∞" }
        let rounded = Int(db.rounded())
        return rounded > 0 ? "+\(rounded) dB" : "\(rounded) dB"
    }
}

/// Small square toggle button used for M and S in matrix cells.
struct MuteSoloButton: View {
    let letter: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 18)
                .background(isActive ? activeColor : Color.secondary.opacity(0.18))
                .foregroundStyle(isActive ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
