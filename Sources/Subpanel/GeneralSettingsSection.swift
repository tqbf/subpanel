import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var showInMenuBar = MenuBarItem.isEnabled

    var body: some View {
        Section {
            Toggle("Show Subpanel in the menu bar", isOn: $showInMenuBar)
                .onChange(of: showInMenuBar) { _, enabled in
                    apply(enabled)
                }
                .onAppear { showInMenuBar = MenuBarItem.isEnabled }
            if MenuBarItem.needsApproval {
                Button("Allow in Login Items…", action: ServiceManager.openLoginItemsSettings)
                    .buttonStyle(.link)
            }
            Text("The menu lists your apps and whether each one is listening, and opens this window. It starts at login. The proxy runs whether or not either app is open.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ enabled: Bool) {
        guard enabled != MenuBarItem.isEnabled else { return }
        do {
            try MenuBarItem.set(enabled)
        } catch {
            model.actionError = error.localizedDescription
        }
        // Registering can land in "requires approval", which isn't "on".
        showInMenuBar = MenuBarItem.isEnabled
    }
}
