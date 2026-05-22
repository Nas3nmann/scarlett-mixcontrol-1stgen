import SwiftUI
import AppKit

// Swift Package executables don't have an Info.plist marking them as regular
// apps; without help the window comes up behind other apps with no Dock icon.
// Set activation policy after launch via an NSApplicationDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ScarlettApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = MixerState()

    var body: some Scene {
        Window("Scarlett MixControl", id: "main") {
            ContentView(state: state)
        }
        .windowResizability(.contentSize)
    }
}
