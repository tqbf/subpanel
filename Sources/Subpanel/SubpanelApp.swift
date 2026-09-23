import SwiftUI

/// The menu-bar app (`LSUIElement`: no Dock icon). Its scenes:
///
/// - the menu-bar menu — the everyday surface;
/// - "Apps", the management window;
/// - "Welcome", shown once on first run;
/// - Settings.
///
/// Quitting it never affects routing: the proxy is a separate launchd job.
struct SubpanelApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarIcon()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Window("Subpanel Apps", id: WindowID.apps) {
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
