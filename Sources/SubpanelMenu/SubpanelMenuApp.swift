import SwiftUI

/// Subpanel Menu: the menu-bar app. A small login item bundled inside
/// Subpanel.app (`Contents/Library/LoginItems/SubpanelMenu.app`). It lists
/// the registered apps, shows which have a process listening, opens them,
/// and opens the full Subpanel app. Nothing else — management lives there.
@main
struct SubpanelMenuApp: App {
    @State private var model = MenuModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
