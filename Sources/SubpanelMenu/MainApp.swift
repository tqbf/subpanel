import AppKit
import SubpanelCore

/// Finds and opens the full Subpanel app — the bundle this login item lives
/// inside (`Subpanel.app/Contents/Library/LoginItems/SubpanelMenu.app`), or
/// failing that, whatever copy Launch Services knows by bundle identifier.
@MainActor
enum MainApp {
    static func open() {
        guard let url = location else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    static var location: URL? {
        let enclosing = Bundle.main.bundleURL
            .deletingLastPathComponent()  // LoginItems
            .deletingLastPathComponent()  // Library
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // Subpanel.app
        if Bundle(url: enclosing)?.bundleIdentifier == SubpanelConstants.appBundleIdentifier {
            return enclosing
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: SubpanelConstants.appBundleIdentifier)
    }
}
