import AppKit
import ServiceManagement
import SubpanelCore

/// The menu-bar app ("Subpanel Menu"), a login item bundled inside this app
/// at `Contents/Library/LoginItems/SubpanelMenu.app`. Registering it starts
/// it now and at every login; unregistering quits it.
enum MenuBarItem {
    private static var service: SMAppService {
        SMAppService.loginItem(identifier: SubpanelConstants.menuBundleIdentifier)
    }

    static var isEnabled: Bool {
        service.status == .enabled
    }

    static var needsApproval: Bool {
        service.status == .requiresApproval
    }

    static var isRegistered: Bool {
        service.status != .notRegistered
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try service.register()
            launchIfNeeded()
        } else {
            try service.unregister()
        }
    }

    /// `register()` doesn't always launch the item right away; make sure it's
    /// running so the icon appears now, not at next login.
    static func launchIfNeeded() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: SubpanelConstants.menuBundleIdentifier)
        guard running.isEmpty else { return }
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems/SubpanelMenu.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
