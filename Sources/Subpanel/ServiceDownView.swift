import SwiftUI

/// Shown in place of content when the proxy isn't answering, with the one
/// action that fixes the specific problem.
struct ServiceDownView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Subpanel Isn't Running", systemImage: "exclamationmark.triangle")
        } description: {
            Text(explanation)
        } actions: {
            switch model.registration {
            case .requiresApproval:
                Button("Open Login Items Settings", action: ServiceManager.openLoginItemsSettings)
            case .notFound:
                EmptyView()
            case .enabled:
                Button("Restart Service", action: restart)
                    .disabled(model.isChangingService)
            case .notRegistered:
                Button("Start Service", action: repair)
                    .disabled(model.isChangingService)
            }
        }
    }

    private var explanation: String {
        switch model.registration {
        case .requiresApproval:
            "Subpanel's background service is turned off in System Settings → General → Login Items."
        case .notFound:
            "This copy of Subpanel.app is missing its background service. Reinstall Subpanel."
        case .enabled:
            "The background service is installed but isn't answering at subpanel.localhost."
        case .notRegistered:
            "The background service that serves *.localhost isn't installed."
        }
    }

    private func restart() {
        Task { await model.restartService() }
    }

    private func repair() {
        Task { await model.repairService() }
    }
}
