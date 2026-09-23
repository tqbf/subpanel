import SwiftUI

/// The top of the menu: is the proxy up, how many apps — and, when it's
/// down, the one action that fixes it.
struct MenuStatusSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch model.health {
        case .checking:
            Text("Checking Subpanel…")
        case .running:
            Label("Proxy running", systemImage: "circle.fill")
            Text(model.apps.count == 1 ? "1 app" : "\(model.apps.count) apps")
        case .notResponding:
            Label("Proxy not running", systemImage: "exclamationmark.triangle")
            switch model.registration {
            case .requiresApproval:
                Button("Allow in Login Items…", action: ServiceManager.openLoginItemsSettings)
            case .notFound:
                Button("Service Missing — Open Settings…", action: showSettings)
            case .notRegistered, .enabled:
                Button(model.registration == .enabled ? "Restart Service" : "Start Service", action: fixService)
                    .disabled(model.isChangingService)
            }
        }
    }

    private func fixService() {
        Task {
            if model.registration == .enabled {
                await model.restartService()
            } else {
                await model.repairService()
            }
            if model.actionError != nil {
                showSettings()
            }
        }
    }

    private func showSettings() {
        Desktop.activate()
        openSettings()
    }
}
