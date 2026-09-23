import SwiftUI

/// Settings: deliberately small (convention over configuration) — no ports,
/// domains, TLS, or LAN options exist to configure. Three short toolbar
/// tabs, the standard macOS settings shape.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingError = false
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
        .alert("Something Went Wrong", isPresented: $showingError) {
            Button("OK", action: clearError)
        } message: {
            Text(model.actionError ?? "")
        }
        .onChange(of: model.actionError) { _, error in
            showingError = error != nil
        }
        .task { await model.refresh() }
    }

    private func clearError() {
        model.actionError = nil
    }
}
