import SwiftUI

/// Subpanel.app, the full app: an ordinary Dock app whose main window
/// manages the mappings. Its scenes:
///
/// - "Subpanel", the Apps window (opens at launch);
/// - "Welcome", shown once on first run;
/// - Settings.
///
/// The menu-bar item is a separate small app (`SubpanelMenu`, a login item
/// bundled inside this one) that opens this one. Quitting either never
/// affects routing: the proxy is its own launchd job.
struct SubpanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Subpanel", id: WindowID.apps) {
            AppsWindow()
                .environment(model)
        }
        .defaultSize(width: Theme.appsDefaultWidth, height: Theme.appsDefaultHeight)
        .windowResizability(.contentMinSize)

        Window("Welcome to Subpanel", id: WindowID.welcome) {
            WelcomeView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
