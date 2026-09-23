import AppKit
import ServiceManagement
import SubpanelCore

/// Headless management from the command line (used by `make install`):
///
///     Subpanel.app/Contents/MacOS/Subpanel --install-service     the port-80 proxy
///     Subpanel.app/Contents/MacOS/Subpanel --uninstall-service
///     Subpanel.app/Contents/MacOS/Subpanel --service-status
///     Subpanel.app/Contents/MacOS/Subpanel --install-menu        the menu-bar app
///     Subpanel.app/Contents/MacOS/Subpanel --uninstall-menu
enum ServiceCommand {
    case install
    case uninstall
    case status
    case installMenu
    case uninstallMenu

    init?(arguments: [String]) {
        switch arguments.dropFirst().first {
        case "--install-service": self = .install
        case "--uninstall-service": self = .uninstall
        case "--service-status": self = .status
        case "--install-menu": self = .installMenu
        case "--uninstall-menu": self = .uninstallMenu
        default: return nil
        }
    }

    func run() -> Int32 {
        let agent = SMAppService.agent(plistName: SubpanelConstants.servicePlistName)
        let menu = SMAppService.loginItem(identifier: SubpanelConstants.menuBundleIdentifier)
        do {
            switch self {
            case .installMenu:
                try? menu.unregister()
                try menu.register()
                launchMenuIfNeeded()
                print("registered menu-bar item \(SubpanelConstants.menuBundleIdentifier): \(describe(menu.status))")
            case .uninstallMenu:
                try menu.unregister()
                print("unregistered menu-bar item \(SubpanelConstants.menuBundleIdentifier)")
            case .install:
                // Re-register so the job points at *this* copy of the app.
                try? agent.unregister()
                try agent.register()
                print("registered \(SubpanelConstants.serviceLabel): \(describe(agent.status))")
                print("agent instructions: \(SubpanelConstants.controlBaseURL())/instructions")
            case .uninstall:
                try agent.unregister()
                print("unregistered \(SubpanelConstants.serviceLabel)")
            case .status:
                print("\(SubpanelConstants.serviceLabel): \(describe(agent.status))")
                print("\(SubpanelConstants.menuBundleIdentifier): \(describe(menu.status))")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Subpanel: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    /// `register()` doesn't always launch a login item immediately. From the
    /// command line, launch it synchronously (in the background) so the
    /// process doesn't exit before Launch Services acts.
    private func launchMenuIfNeeded() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SubpanelConstants.menuBundleIdentifier).isEmpty else {
            return
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-g", Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems/SubpanelMenu.app").path]
        try? process.run()
        process.waitUntilExit()
    }

    private func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "enabled"
        case .requiresApproval: "requires approval (System Settings → General → Login Items)"
        case .notFound: "not found (is this a bundle built by build.sh?)"
        case .notRegistered: "not registered"
        @unknown default: "unknown"
        }
    }
}
