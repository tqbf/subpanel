import SubpanelCore
import SwiftUI

/// The whole menu:
///
///     Apps                              ← section header
///     ● wiki        node · 127.0.0.1:43127
///     ○ phone       Not listening · 127.0.0.1:5173
///     ─────────
///     Open Subpanel                 ⌘O
///     ─────────
///     Quit Subpanel Menu            ⌘Q
///
/// Clicking an app opens its `.localhost` URL. A filled dot means a process
/// is listening on the app's port right now; hollow means nothing is.
struct MenuContent: View {
    @Environment(MenuModel.self) private var model

    var body: some View {
        switch model.health {
        case .checking:
            Text("Checking Subpanel…")
        case .notResponding:
            Text("Subpanel's service isn't running")
        case .running where model.apps.isEmpty:
            Text("No apps registered")
        case .running:
            Section("Apps") {
                ForEach(model.apps) { app in
                    AppMenuItem(app: app)
                }
            }
        }

        Divider()
        Button("Open Subpanel", action: MainApp.open)
            .keyboardShortcut("o")
        Divider()
        Button("Quit Subpanel Menu", action: quit)
            .keyboardShortcut("q")
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
