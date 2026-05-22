import SwiftUI
import AppKit

// Swift Package executables don't have an Info.plist marking them as regular
// apps; without help the window comes up behind other apps with no Dock icon.
// Set activation policy after launch via an NSApplicationDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Force AppKit-backed controls (Picker .menu = NSPopUpButton, Menu,
        // context menus, etc.) to use dark appearance regardless of the
        // user's system setting. SwiftUI's .preferredColorScheme only
        // affects SwiftUI views, not the embedded AppKit controls.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

@main
struct ScarlettApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = MixerState()

    var body: some Scene {
        Window("Scarlett MixControl", id: "main") {
            ContentView(state: state)
                .frame(
                    minWidth: 960,
                    idealWidth: 1340,
                    maxWidth: .infinity,
                    minHeight: 620,
                    idealHeight: 720,
                    maxHeight: .infinity
                )
        }
        .windowResizability(.contentSize)
    }
}
