import SwiftUI

/// Settings: deliberately small (convention over configuration) — no ports,
/// domains, TLS, or LAN options exist to configure. Three short toolbar
/// tabs, the standard macOS settings shape.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                SettingsPane(height: Theme.settingsGeneralHeight) {
                    GeneralSettingsSection()
                    DataSettingsSection()
                }
            }
            Tab("Service", systemImage: "point.3.connected.trianglepath.dotted", value: .service) {
                SettingsPane(height: Theme.settingsServiceHeight) {
                    ServiceSettingsSection()
                }
            }
            Tab("Diagnostics", systemImage: "stethoscope", value: .diagnostics) {
                SettingsPane(height: Theme.settingsDiagnosticsHeight) {
                    DiagnosticsSection()
                }
            }
        }
        .actionErrorAlert()
        .task { await model.refresh() }
    }
}
