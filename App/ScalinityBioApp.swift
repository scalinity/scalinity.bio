import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // When running as a SwiftPM executable (not a bundled .app),
        // macOS may not treat the process as a regular UI application.
        // Force UI activation so a window appears when running from Xcode.
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first {
                window.center()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct ScalinityBioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}


