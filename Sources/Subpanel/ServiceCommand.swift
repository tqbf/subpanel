import Foundation
import ServiceManagement
import SubpanelCore

/// Headless service management from the command line:
///
///     Subpanel.app/Contents/MacOS/Subpanel --install-service
///     Subpanel.app/Contents/MacOS/Subpanel --uninstall-service
///     Subpanel.app/Contents/MacOS/Subpanel --service-status
enum ServiceCommand {
    case install
    case uninstall
    case status

    init?(arguments: [String]) {
        switch arguments.dropFirst().first {
        case "--install-service": self = .install
        case "--uninstall-service": self = .uninstall
        case "--service-status": self = .status
        default: return nil
        }
    }

    func run() -> Int32 {
        let agent = SMAppService.agent(plistName: SubpanelConstants.servicePlistName)
        do {
            switch self {
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
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Subpanel: \(error.localizedDescription)\n".utf8))
            return 1
        }
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
