import SwiftUI

/// The menu-bar icon: the breaker-panel glyph, or a warning triangle while
/// the service isn't answering. It exists for the app's whole life, so it's
/// also where polling starts.
struct MenuBarLabel: View {
    @Environment(MenuModel.self) private var model

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
        await MenuSnapshot.runIfRequested()
    }
}
