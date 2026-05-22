import SwiftUI
import ScarlettCore

enum AppTab: String, CaseIterable, Identifiable {
    case mixer, routing, presets, device

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mixer:   return "Mixer"
        case .routing: return "Routing"
        case .presets: return "Presets"
        case .device:  return "Device"
        }
    }
    var systemImage: String {
        switch self {
        case .mixer:   return "slider.vertical.3"
        case .routing: return "arrow.triangle.branch"
        case .presets: return "bookmark"
        case .device:  return "gearshape"
        }
    }
}

struct ContentView: View {
    @Bindable var state: MixerState
    @State private var tab: AppTab = .mixer
    @State private var sidebarCollapsed: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.divider).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: sidebarCollapsed)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .task { state.startMeterPolling() }
    }

    private var sidebarWidth: CGFloat { sidebarCollapsed ? 56 : 200 }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            ForEach(AppTab.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
            sidebarFooter
        }
        .frame(width: sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
    }

    private var sidebarHeader: some View {
        HStack {
            if !sidebarCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scarlett 8i6").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("1st Gen").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                sidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 22)
                    .background(Theme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        }
        .padding(.horizontal, sidebarCollapsed ? 0 : 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
    }

    @ViewBuilder
    private var sidebarFooter: some View {
        if sidebarCollapsed {
            VStack(spacing: 8) {
                Image(systemName: state.connectionError == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(state.connectionError == nil ? .green : .red)
                    .help(state.connectionError ?? "Connected")
                Image(systemName: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(state.syncLocked ? .green : .orange)
                    .help(state.syncLocked ? "Clock locked" : "No clock lock")
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                statusBadge
                Text("Firmware \(state.firmware)").font(.caption2).foregroundStyle(Theme.textSecondary)
                Text("Serial \(state.serial)").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sidebarRow(_ item: AppTab) -> some View {
        let selected = tab == item
        return Button {
            tab = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 20)
                if !sidebarCollapsed {
                    Text(item.label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, sidebarCollapsed ? 0 : 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
            .background(selected ? Theme.panelRaised : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, sidebarCollapsed ? 6 : 8)
        }
        .buttonStyle(.plain)
        .help(sidebarCollapsed ? item.label : "")
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(state.connectionError == nil ? "Connected" : "Error",
                  systemImage: state.connectionError == nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(state.connectionError == nil ? .green : .red)
            Label(state.syncLocked ? "Clock locked" : "No clock lock",
                  systemImage: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(state.syncLocked ? .green : .orange)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .mixer:   MixerPaneView(state: state)
        case .routing: RoutingView(state: state)
        case .presets: PresetsView(state: state)
        case .device:  DeviceView(state: state)
        }
    }
}

// MARK: - Mixer pane

struct MixerPaneView: View {
    @Bindable var state: MixerState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MatrixMixerView(state: state)
                masterSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var masterSection: some View {
        Panel(title: "Master outputs") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    masterStrip(
                        title: "Monitor (Out 1+2)",
                        subtitle: "Rear-panel jacks",
                        db: Binding(get: { state.monitorAtten }, set: { state.userSetMonitorAtten($0) }),
                        leftMuted: state.monitorLMuted,
                        rightMuted: state.monitorRMuted,
                        toggleLeft: { state.userSetSideMute(bus: .monitorLeft, muted: !state.monitorLMuted) },
                        toggleRight: { state.userSetSideMute(bus: .monitorRight, muted: !state.monitorRMuted) },
                        extraButton: AnyView(dimButton)
                    )

                    masterStrip(
                        title: "Phones (Out 3+4)",
                        subtitle: "Front jack / speakers",
                        db: Binding(get: { state.phonesAtten }, set: { state.userSetPhonesAtten($0) }),
                        leftMuted: state.phonesLMuted,
                        rightMuted: state.phonesRMuted,
                        toggleLeft: { state.userSetSideMute(bus: .phonesLeft, muted: !state.phonesLMuted) },
                        toggleRight: { state.userSetSideMute(bus: .phonesRight, muted: !state.phonesRMuted) },
                        extraButton: nil
                    )

                    masterControls
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func masterStrip(
        title: String,
        subtitle: String,
        db: Binding<Double>,
        leftMuted: Bool, rightMuted: Bool,
        toggleLeft: @escaping () -> Void,
        toggleRight: @escaping () -> Void,
        extraButton: AnyView?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .center) {
                Text("\(Int(db.wrappedValue)) dB")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 50, alignment: .trailing)
                Slider(value: db, in: -60...0, step: 1)
                    .contextMenu {
                        Button("Reset to 0 dB") { db.wrappedValue = 0 }
                    }
            }
            HStack(spacing: 6) {
                MasterButton(label: "Mute L", active: leftMuted,
                             activeColor: Theme.muteActive, action: toggleLeft)
                MasterButton(label: "Mute R", active: rightMuted,
                             activeColor: Theme.muteActive, action: toggleRight)
                if let extra = extraButton {
                    extra
                }
            }
        }
        .frame(width: 320, alignment: .leading)
    }

    private var dimButton: AnyView {
        AnyView(
            MasterButton(
                label: "Dim −20",
                active: state.dimEnabled,
                activeColor: Theme.soloActive,
                action: { state.userToggleDim() }
            )
        )
    }

    private var masterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Master").font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
            Text("Affects all outputs").font(.caption).foregroundStyle(Theme.textSecondary)
            MasterButton(label: state.masterMuted ? "Master muted" : "Mute all",
                         active: state.masterMuted, activeColor: Theme.muteActive) {
                state.userSetMasterMute(!state.masterMuted)
            }
            Button("Save to hardware") { state.saveToFlash() }
                .controlSize(.regular)
                .help("Persist current settings to device flash so they survive a power cycle.")
        }
        .frame(width: 200, alignment: .leading)
    }
}

// MARK: - Routing pane

struct RoutingView: View {
    @Bindable var state: MixerState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Routing").font(.title2).bold().foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("Each output picks ONE source. Combine sources first in the Mixer (M1–M6) and route those here.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 380)
                }

                Panel(title: "Output assignments") {
                    VStack(spacing: 8) {
                        stereoRouteRow("Monitor",  "Outputs 1+2 (rear jacks)", .monitorLeft, .monitorRight)
                        stereoRouteRow("Phones",   "Outputs 3+4 (front jack / speakers)", .phonesLeft, .phonesRight)
                        stereoRouteRow("S/PDIF",   "Digital out (RCA)", .spdifLeft, .spdifRight)
                    }
                }

                Text("Tip: routing reads always return 00 00 on the 1st-gen 8i6 — this app remembers your last setup in UserDefaults and re-pushes it to the device on launch.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private func stereoRouteRow(_ title: String, _ subtitle: String, _ left: Route, _ right: Route) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 220, alignment: .leading)

            routePicker(label: "L", route: left)
            routePicker(label: "R", route: right)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func routePicker(label: String, route: Route) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).frame(width: 12)
            Picker("", selection: Binding(
                get: { state.routes[route] ?? .off },
                set: { state.userSetRoute(route, to: $0) }
            )) {
                ForEach(MixBus.availableOn8i6) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
    }
}

// MARK: - Device pane

struct DeviceView: View {
    @Bindable var state: MixerState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Device").font(.title2).bold().foregroundStyle(Theme.textPrimary)

                Panel(title: "Hardware") {
                    InfoGrid(rows: hardwareRows)
                }

                Panel(title: "Connection & driver") {
                    InfoGrid(rows: connectionRows)
                    Text("The 1st-gen Scarlett 8i6 is USB Audio Class 2.0 — no Focusrite kernel driver, no installer. macOS's built-in usbaudiod claims the audio + MIDI interfaces; this app talks to endpoint 0 directly for DSP control transfers, which doesn't conflict.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                }

                Panel(title: "Clock & sample rate") {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Clock source").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Picker("", selection: Binding(
                                get: { state.clock },
                                set: { state.userSetClock($0) }
                            )) {
                                Text(ClockSource.internalClock.displayName).tag(ClockSource.internalClock)
                                Text(ClockSource.spdif.displayName).tag(ClockSource.spdif)
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 160)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sample rate").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            Picker("", selection: Binding(
                                get: { state.sampleRate },
                                set: { state.userSetSampleRate($0) }
                            )) {
                                Text("44.1 kHz").tag(UInt32(44100))
                                Text("48 kHz").tag(UInt32(48000))
                                Text("88.2 kHz").tag(UInt32(88200))
                                Text("96 kHz").tag(UInt32(96000))
                            }
                            .pickerStyle(.menu).labelsHidden().frame(width: 160)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sync status").font(.subheadline).foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 6) {
                                Image(systemName: state.syncLocked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(state.syncLocked ? .green : .orange)
                                Text(state.syncLocked ? "Locked" : "No lock")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.top, 2)
                        }
                        Spacer()
                    }
                    Text("Changing the sample rate while audio is streaming will interrupt usbaudiod and may glitch playback.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                }

                Panel(title: "Persistence") {
                    HStack {
                        Button("Save to hardware") { state.saveToFlash() }
                            .help("Writes current state to the device's flash so it survives a power cycle. Flash has finite write cycles; don't call this every change.")
                        Spacer()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
    }

    private var hardwareRows: [InfoGrid.Row] {
        [
            .init(label: "Model",        value: "Scarlett 8i6"),
            .init(label: "Generation",   value: "1st Gen (released ~2012)"),
            .init(label: "Firmware",     value: state.firmware),
            .init(label: "Serial",       value: state.serial),
            .init(label: "Vendor",       value: "Focusrite (0x1235)"),
            .init(label: "Product",      value: String(format: "0x%04X", ScarlettDevice.scarlett8i6Gen1PID)),
        ]
    }

    private var connectionRows: [InfoGrid.Row] {
        let conn: String
        if state.device == nil { conn = "Not found" }
        else if state.connectionError != nil { conn = "Error" }
        else { conn = "Connected via USB" }

        return [
            .init(label: "Status",       value: conn,
                  valueColor: state.device == nil || state.connectionError != nil ? .red : .green),
            .init(label: "Class",        value: "USB Audio Class 2.0 (vendor-extended)"),
            .init(label: "Audio path",   value: "Owned by macOS usbaudiod"),
            .init(label: "MIDI path",    value: "Owned by macOS MIDIServer"),
            .init(label: "DSP control",  value: "Endpoint 0 (this app)"),
            .init(label: "Error",        value: state.connectionError ?? "—",
                  valueColor: state.connectionError == nil ? Theme.textSecondary : .red),
        ]
    }
}

/// Simple label-value table for the Device pane.
struct InfoGrid: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var valueColor: Color = Theme.textPrimary
    }
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.value)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(row.valueColor)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Shared components

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(16)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MasterButton: View {
    let label: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .frame(minWidth: 70)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(active ? activeColor : Theme.panelRaised)
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

struct LevelRow: View {
    let label: String
    let db: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            HorizontalMeterBar(db: db)
            Text(db.isFinite ? String(format: "%5.1f", db) : "-inf")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct HorizontalMeterBar: View {
    let db: Double
    private static let barWidth: CGFloat = 220

    private var fillWidth: CGFloat {
        let clamped = max(-60, min(0, db.isFinite ? db : -60))
        return CGFloat(clamped + 60) / 60 * Self.barWidth
    }

    private var color: Color {
        if db > -3 { return Theme.meterHigh }
        if db > -12 { return Theme.meterMid }
        return Theme.meterLow
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.faderTrack)
                .frame(width: Self.barWidth, height: 8)
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: fillWidth, height: 8)
        }
        .frame(width: Self.barWidth, height: 8)
    }
}
