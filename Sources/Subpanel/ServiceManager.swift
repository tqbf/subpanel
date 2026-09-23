import Foundation
import ServiceManagement
import SubpanelCore

/// Installs and controls `subpanel-service`, the LaunchAgent bundled at
/// `Subpanel.app/Contents/Library/LaunchAgents` (plans/service-lifecycle.md).
///
/// Everything here is unprivileged: the agent runs as the user, and launchd
/// binds port 80 for it. The only operations are register, unregister, and
/// restart — there's no general-purpose command channel.
struct ServiceManager: Sendable {
    enum Registration: Equatable, Sendable {
        case notRegistered
        case enabled
        /// The user switched it off in System Settings → Login Items.
        case requiresApproval
        /// The app bundle doesn't contain the agent plist (not built by build.sh).
        case notFound
    }

    private var agent: SMAppService {
        SMAppService.agent(plistName: SubpanelConstants.servicePlistName)
    }

    var registration: Registration {
        switch agent.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    /// Registers the agent; launchd starts it immediately and at every login.
    func install() throws {
        try agent.register()
    }

    /// Unregisters and registers again — fixes a registration that points at
    /// an old copy of the app, or a stuck job.
    func reinstall() async throws {
        try? await agent.unregister()
        try agent.register()
    }

    /// Kills and relaunches the running job. launchd keeps port 80 open
    /// throughout, so connections made meanwhile just wait.
    func restart() async throws {
        let target = "gui/\(getuid())/\(SubpanelConstants.serviceLabel)"
        try await Self.launchctl(["kickstart", "-k", target])
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func launchctl(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw CocoaError(.executableLoad, userInfo: [
                NSLocalizedDescriptionKey: "launchctl \(arguments.joined(separator: " ")) failed (exit \(status)).",
            ])
        }
    }
}
