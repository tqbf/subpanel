import SwiftUI

/// The welcome window's one-line answer to "is it working?".
struct WelcomeStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isRunning {
            Label("Subpanel is running.", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        } else if model.isChangingService || model.health == .checking {
            HStack(spacing: Theme.tightSpacing) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting Subpanel…")
                    .foregroundStyle(.secondary)
            }
        } else if model.registration == .requiresApproval {
            VStack(spacing: Theme.tightSpacing) {
                Label("Allow Subpanel's service in Login Items to finish setup.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Button("Open Login Items Settings", action: ServiceManager.openLoginItemsSettings)
            }
        } else {
            VStack(spacing: Theme.tightSpacing) {
                Label("Subpanel's service isn't running yet.", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Button("Start Service", action: start)
            }
        }
    }

    private func start() {
        Task { await model.repairService() }
    }
}
