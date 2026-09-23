import SwiftUI

/// The menu-bar icon. It lives for the app's whole life, so it also starts
/// polling and, on first launch, opens the welcome window.
struct MenuBarIcon: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        Group {
            if model.health == .notResponding {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(nsImage: MenuBarGlyph.image)
            }
        }
        .accessibilityLabel(model.health == .notResponding ? "Subpanel: service not running" : "Subpanel")
        .task { await start() }
    }

    private func start() async {
        model.start()
        if DevSnapshot.directory != nil {
            await DevSnapshot.run(openWindow: openWindow, openSettings: openSettings)
            return
        }
        if !hasSeenWelcome {
            openWindow(id: WindowID.welcome)
            Desktop.activate()
        }
    }
}
