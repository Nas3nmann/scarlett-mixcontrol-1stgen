import SwiftUI
import ScarlettCore

/// A vertical mixer strip for one matrix channel in the currently selected bus.
/// Layout mirrors Focusrite Control 2: name + source + colored underline at top,
/// fader with dB scale and meter in the middle, M/S buttons at the bottom.
struct ChannelStrip: View {
    let channel: Int
    @Bindable var state: MixerState
    @State private var editingName: Bool = false
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let bus = state.selectedBus
        let busIdx = Int(bus.rawValue)
        let source = state.mixerSources[channel]
        let isMuted = state.mixerMutes[channel][busIdx]
        let isSoloed = state.mixerSolos[channel][busIdx]

        VStack(spacing: 6) {
            header(source: source)
            inputSwitch(source: source)
            panSlider
            fader
            peakReadout
            mutesolo(isMuted: isMuted, isSoloed: isSoloed)
        }
        .frame(width: 100)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            // Subtle bottom border to make linked pairs visually obvious.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(state.isLinked(channel) ? Theme.muteActive.opacity(0.45) : .clear, lineWidth: 1)
        )
    }

    // MARK: - Contextual hardware-input switch
    //
    // When this strip's source is one of the 8i6's software-configurable
    // hardware inputs, surface the relevant switch right here on the strip
    // so the user doesn't have to navigate elsewhere.  Otherwise reserve
    // the same vertical space (an empty placeholder) to keep strip heights
    // consistent across the row.

    @ViewBuilder
    private func inputSwitch(source: SignalSource) -> some View {
        switch source {
        case .analog1:
            ImpedanceSwitch(value: Binding(
                get: { state.impedance1 },
                set: { state.userSetImpedance(channel: 1, mode: $0) }
            ))
        case .analog2:
            ImpedanceSwitch(value: Binding(
                get: { state.impedance2 },
                set: { state.userSetImpedance(channel: 2, mode: $0) }
            ))
        case .analog3:
            HiLoSwitch(value: Binding(
                get: { state.hi3 },
                set: { state.userSetHiLo(channel: 3, hi: $0) }
            ))
        case .analog4:
            HiLoSwitch(value: Binding(
                get: { state.hi4 },
                set: { state.userSetHiLo(channel: 4, hi: $0) }
            ))
        default:
            // Reserve the same vertical footprint so every strip aligns.
            Color.clear.frame(height: 22)
        }
    }

    // MARK: - Header

    private func header(source: SignalSource) -> some View {
        VStack(spacing: 3) {
            nameField
            Picker("", selection: Binding(
                get: { state.mixerSources[channel] },
                set: { state.userSetMixerSource(channel: channel, source: $0) }
            )) {
                ForEach(SignalSource.availableOn8i6) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.mini)
            .tint(Theme.textSecondary)

            Rectangle()
                .fill(source.accentColor)
                .frame(height: 2)
                .padding(.horizontal, 2)
        }
    }

    /// Channel name — defaults to "Ch N", double-click to rename.
    private var nameField: some View {
        let stored = state.mixerNames[channel]
        let displayed = stored.isEmpty ? "Ch \(channel + 1)" : stored
        return Group {
            if editingName {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { editingName = false }
                    .onAppear {
                        nameDraft = stored
                        nameFocused = true
                    }
            } else {
                Text(displayed)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        nameDraft = stored
                        editingName = true
                    }
                    .help("Double-click to rename")
            }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        state.userSetChannelName(channel: channel, name: trimmed)
        editingName = false
    }

    // MARK: - Fader column

    private var fader: some View {
        let bus = state.selectedBus
        let busIdx = Int(bus.rawValue)
        let pair = MixerState.pairIndex(of: bus)
        let level = state.mixerLevels[channel][pair]
        let meterDb = liveLevel(from: state.peaks)
        let peakDb  = liveLevel(from: state.peaksHeld)

        let maxDb = liveLevel(from: state.peaksMax)

        return HStack(alignment: .center, spacing: 4) {
            VerticalFader(db: Binding(
                get: { level },
                set: { state.userSetMixerLevel(channel: channel, pair: pair, level: $0) }
            ))
            .opacity(state.mixerMutes[channel][busIdx] ? 0.4 : 1.0)
            .contextMenu {
                Button("Reset fader to 0 dB") {
                    state.userSetMixerLevel(channel: channel, pair: pair, level: 0)
                }
            }

            VerticalMeter(db: meterDb, peakDb: peakDb, maxPeakDb: maxDb)

            DbScale()
        }
        .frame(height: 220)
        .overlay(alignment: .topTrailing) {
            Text(formatDb(level))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(state.mixerMutes[channel][busIdx] ? Theme.muteActive : Theme.textSecondary)
                .padding(.top, -16)
        }
    }

    private var panSlider: some View {
        let pair = MixerState.pairIndex(of: state.selectedBus)
        let pan = state.mixerPans[channel][pair]
        return VStack(spacing: 1) {
            Slider(
                value: Binding(
                    get: { pan },
                    set: { state.userSetMixerPan(channel: channel, pair: pair, pan: $0) }
                ),
                in: -1...1
            )
            .controlSize(.mini)
            .contextMenu {
                Button("Reset pan to center") {
                    state.userSetMixerPan(channel: channel, pair: pair, pan: 0)
                }
            }
            Text(panLabel(pan))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func panLabel(_ pan: Double) -> String {
        if abs(pan) < 0.02 { return "C" }
        let pct = Int(round(abs(pan) * 100))
        return pan < 0 ? "L\(pct)" : "R\(pct)"
    }

    /// Maps the strip's current source selection to the matching slot in a
    /// `PeakReading` so we can render both live and peak-hold levels.
    private func liveLevel(from peaks: PeakReading) -> Double {
        switch state.mixerSources[channel] {
        case .analog1: return peaks.inputs[0]
        case .analog2: return peaks.inputs[1]
        case .analog3: return peaks.inputs[2]
        case .analog4: return peaks.inputs[3]
        case .spdif1:  return peaks.inputs[8]
        case .spdif2:  return peaks.inputs[9]
        case .daw1:    return peaks.daw[0]
        case .daw2:    return peaks.daw[1]
        case .daw3:    return peaks.daw[2]
        case .daw4:    return peaks.daw[3]
        case .daw5:    return peaks.daw[4]
        case .daw6:    return peaks.daw[5]
        default:       return -.infinity
        }
    }

    private var peakReadout: some View {
        let peak = liveLevel(from: state.peaksHeld)
        let max  = liveLevel(from: state.peaksMax)
        return VStack(spacing: 1) {
            Text(formatPeak("Pk", peak))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            Button {
                state.clearMaxPeak(forSource: state.mixerSources[channel])
            } label: {
                Text(formatPeak("Mx", max))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.meterHigh)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to reset this channel's max peak")
        }
        .frame(maxWidth: .infinity)
    }

    private func formatPeak(_ label: String, _ db: Double) -> String {
        if !db.isFinite || db <= -60 { return "\(label) −∞" }
        return String(format: "%@ %5.1f", label, db)
    }

    // MARK: - Mute / Solo

    private func mutesolo(isMuted: Bool, isSoloed: Bool) -> some View {
        HStack(spacing: 3) {
            StripButton(letter: "M", active: isMuted, activeColor: Theme.muteActive) {
                state.userToggleMixerMute(channel: channel, bus: state.selectedBus)
            }
            StripButton(letter: "S", active: isSoloed, activeColor: Theme.soloActive) {
                state.userToggleMixerSolo(channel: channel, bus: state.selectedBus)
            }
            LinkButton(active: state.isLinked(channel)) {
                state.userToggleLink(channel: channel)
            }
        }
    }

    private func formatDb(_ db: Double) -> String {
        if db <= -60 { return "−∞" }
        let r = Int(db.rounded())
        return r > 0 ? "+\(r)" : "\(r)"
    }
}

/// Compact Line/Instrument toggle for the combo-input strips (Analog 1, 2).
struct ImpedanceSwitch: View {
    @Binding var value: Impedance

    var body: some View {
        Picker("", selection: $value) {
            Text("Line").tag(Impedance.line)
            Text("Inst").tag(Impedance.instrument)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Compact Lo/Hi gain toggle for the line-input strips (Analog 3, 4).
struct HiLoSwitch: View {
    @Binding var value: Bool

    var body: some View {
        Picker("", selection: $value) {
            Text("Lo").tag(false)
            Text("Hi").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .frame(height: 22)
    }
}

/// Small button shown on each strip — toggles whether this channel is in a
/// linked stereo pair with its even/odd partner.  Active = paired.
struct LinkButton: View {
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(active ? Theme.muteActive : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(active ? "Linked stereo pair (click to unlink)" : "Link with adjacent channel")
    }
}

struct StripButton: View {
    let letter: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 26, height: 22)
                .background(active ? activeColor : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }
}
