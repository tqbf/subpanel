import SwiftUI

struct GeneralSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Section {
            Toggle("Open Subpanel at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    apply(enabled)
                }
            Text("The proxy runs as a background service whether or not this menu-bar app is open.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            model.actionError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
