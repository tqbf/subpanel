import SwiftUI

/// Whether the service's LaunchAgent is registered with launchd, and the
/// fix when it isn't.
struct LoginItemLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.registration {
        case .enabled:
            Text("Enabled")
                .foregroundStyle(.secondary)
        case .notRegistered:
            Text("Not installed")
                .foregroundStyle(.secondary)
        case .notFound:
            Text("Missing from this app bundle")
                .foregroundStyle(.secondary)
        case .requiresApproval:
            Button("Turned Off — Open Login Items…", action: ServiceManager.openLoginItemsSettings)
                .buttonStyle(.link)
        }
    }
}
