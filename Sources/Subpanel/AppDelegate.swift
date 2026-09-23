import AppKit

/// Subpanel.app is an ordinary windowed app: closing its window quits it.
/// The menu-bar app and the proxy service are separate processes, so
/// quitting here never affects either.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
