import SwiftUI
import ScarlettCore

struct ContentView: View {
    @Bindable var state: MixerState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                metersSection
                Divider()
                inputSwitchesSection
                Divider()
                routingSection
                Divider()
                MatrixMixerView(state: state)
                Divider()
                monitorSection
                Divider()
                phonesSection
                Divider()
                deviceSection
                Divider()
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 860, idealWidth: 940, minHeight: 760, idealHeight: 1040)
        .task { state.startMeterPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("Scarlett 8i6 (1st Gen)").font(.title2).bold()
                Text("Firmware \(state.firmware) · Serial \(state.serial)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let err = state.connectionError {
                    Text(err)
                        .font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: 320, alignment: .trailing)
                        .lineLimit(2)
                } else if state.metersStale {
                    Label("meters stale", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("connected", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                Label(
                    state.syncLocked ? "Clock: Locked" : "Clock: No lock",
                    systemImage: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption).foregroundStyle(state.syncLocked ? .green : .orange)
            }
        }
    }

    // MARK: - Meters

    private var metersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak meters").font(.headline)
            HStack(alignment: .top, spacing: 18) {
                meterColumn(title: "Inputs 1..6", values: Array(state.peaks.inputs.prefix(6)))
                meterColumn(title: "S/PDIF L,R",  values: Array(state.peaks.inputs[8..<10]))
                meterColumn(title: "DAW 1..6",    values: state.peaks.daw)
                meterColumn(title: "Mix M1..8",   values: state.peaks.mixer)
            }
        }
    }

    private func meterColumn(title: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.monospaced()).foregroundStyle(.secondary)
            ForEach(Array(values.enumerated()), id: \.offset) { idx, db in
                MeterBar(db: db, label: "\(idx + 1)")
            }
        }
    }

    // MARK: - Input switches

    private var inputSwitchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Input switches").font(.headline)
            HStack(alignment: .top, spacing: 28) {
                // Inputs 1 & 2: line / instrument impedance
                inputCard(title: "Input 1", subtitle: "Combo (mic/line/inst)") {
                    Picker("", selection: Binding(
                        get: { state.impedance1 },
                        set: { state.userSetImpedance(channel: 1, mode: $0) }
                    )) {
                        ForEach(Impedance.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                inputCard(title: "Input 2", subtitle: "Combo (mic/line/inst)") {
                    Picker("", selection: Binding(
                        get: { state.impedance2 },
                        set: { state.userSetImpedance(channel: 2, mode: $0) }
                    )) {
                        ForEach(Impedance.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                // Inputs 3 & 4: hi / lo gain
                inputCard(title: "Input 3", subtitle: "Line (hi/lo gain)") {
                    Picker("", selection: Binding(
                        get: { state.hi3 },
                        set: { state.userSetHiLo(channel: 3, hi: $0) }
                    )) {
                        Text("Lo").tag(false)
                        Text("Hi").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                inputCard(title: "Input 4", subtitle: "Line (hi/lo gain)") {
                    Picker("", selection: Binding(
                        get: { state.hi4 },
                        set: { state.userSetHiLo(channel: 4, hi: $0) }
                    )) {
                        Text("Lo").tag(false)
                        Text("Hi").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    private func inputCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).bold()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content().padding(.top, 2)
        }
        .frame(width: 180, alignment: .leading)
    }

    // MARK: - Routing

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Output routing").font(.headline)
                Spacer()
                Text("Each output picks ONE source. Combine multiple sources via the Matrix Mixer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                stereoRouteRow(
                    title: "Monitor",
                    subtitle: "Outputs 1+2 (rear jacks)",
                    left: .monitorLeft, right: .monitorRight
                )
                stereoRouteRow(
                    title: "Phones",
                    subtitle: "Outputs 3+4 (front jack / speakers)",
                    left: .phonesLeft, right: .phonesRight
                )
                stereoRouteRow(
                    title: "S/PDIF",
                    subtitle: "Digital out (RCA)",
                    left: .spdifLeft, right: .spdifRight
                )
            }
        }
    }

    private func stereoRouteRow(title: String, subtitle: String, left: Route, right: Route) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)

            routePicker(label: "L", route: left)
            routePicker(label: "R", route: right)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func routePicker(label: String, route: Route) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Picker("", selection: Binding(
                get: { state.routes[route] ?? .off },
                set: { state.userSetRoute(route, to: $0) }
            )) {
                ForEach(MixBus.availableOn8i6) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 140)
        }
    }

    // MARK: - Monitor

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitor — Outputs 1+2").font(.headline)
                    Text("Rear-panel jacks").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(state.monitorAtten)) dB")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { state.monitorAtten },
                    set: { state.userSetMonitorAtten($0) }
                ),
                in: -60...0,
                step: 1
            )
            HStack(spacing: 8) {
                sideMuteButton(label: "Mute L", muted: state.monitorLMuted) {
                    state.userSetSideMute(bus: .monitorLeft, muted: !state.monitorLMuted)
                }
                sideMuteButton(label: "Mute R", muted: state.monitorRMuted) {
                    state.userSetSideMute(bus: .monitorRight, muted: !state.monitorRMuted)
                }
                dimButton
                Spacer()
            }
        }
    }

    private var dimButton: some View {
        Button {
            state.userToggleDim()
        } label: {
            Text("Dim −20 dB")
                .font(.caption.bold())
                .frame(minWidth: 90)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(state.dimEnabled ? Color.yellow : Color.secondary.opacity(0.15))
                .foregroundStyle(state.dimEnabled ? .black : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help("Drop monitor outputs by 20 dB. Toggle off to restore.")
    }

    private func sideMuteButton(label: String, muted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .frame(minWidth: 60)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(muted ? Color.red : Color.secondary.opacity(0.15))
                .foregroundStyle(muted ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phones

    private var phonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phones — Outputs 3+4").font(.headline)
                    Text("Front headphone jack / driving the main speakers in your setup").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(state.phonesAtten)) dB")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 60, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { state.phonesAtten },
                    set: { state.userSetPhonesAtten($0) }
                ),
                in: -60...0,
                step: 1
            )
            HStack(spacing: 8) {
                sideMuteButton(label: "Mute L", muted: state.phonesLMuted) {
                    state.userSetSideMute(bus: .phonesLeft, muted: !state.phonesLMuted)
                }
                sideMuteButton(label: "Mute R", muted: state.phonesRMuted) {
                    state.userSetSideMute(bus: .phonesRight, muted: !state.phonesRMuted)
                }
                Spacer()
            }
        }
    }

    // MARK: - Device config

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device").font(.headline)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clock source").font(.subheadline)
                    Picker("", selection: Binding(
                        get: { state.clock },
                        set: { state.userSetClock($0) }
                    )) {
                        // 8i6 has no ADAT; expose only Internal & S/PDIF.
                        Text(ClockSource.internalClock.displayName).tag(ClockSource.internalClock)
                        Text(ClockSource.spdif.displayName).tag(ClockSource.spdif)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample rate").font(.subheadline)
                    Picker("", selection: Binding(
                        get: { state.sampleRate },
                        set: { state.userSetSampleRate($0) }
                    )) {
                        Text("44.1 kHz").tag(UInt32(44100))
                        Text("48 kHz").tag(UInt32(48000))
                        Text("88.2 kHz").tag(UInt32(88200))
                        Text("96 kHz").tag(UInt32(96000))
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                }
                Spacer()
            }
            Text("Changing the sample rate while audio is streaming will interrupt usbaudiod.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Toggle("Master mute", isOn: Binding(
                get: { state.masterMuted },
                set: { state.userSetMasterMute($0) }
            ))
            .toggleStyle(.switch)
            Spacer()
            Button("Save to hardware") { state.saveToFlash() }
                .help("Persist current mixer/routing state to the device's flash so it survives a power cycle.")
        }
    }
}

// MARK: - Meter bar

struct MeterBar: View {
    let db: Double
    let label: String

    private static let barWidth: CGFloat = 100

    private var fillWidth: CGFloat {
        let clamped = max(-60, min(0, db.isFinite ? db : -60))
        return CGFloat(clamped + 60) / 60 * Self.barWidth
    }

    private var color: Color {
        if db > -3   { return .red }
        if db > -12  { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2.monospacedDigit())
                .frame(width: 14, alignment: .trailing)
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: Self.barWidth, height: 10)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: fillWidth, height: 10)
            }
            .frame(width: Self.barWidth, height: 10)
            Text(db.isFinite ? String(format: "%5.1f", db) : "-inf")
                .font(.caption2.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
