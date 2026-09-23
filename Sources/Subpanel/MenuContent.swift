import SubpanelCore
import SwiftUI

/// The menu-bar menu (`.menu` style, so it's a real NSMenu):
///
///     ● Proxy running
///     3 apps
///     ─────────
///     ● wiki            ← click to open http://wiki.localhost
///     ○ phone           ← hollow: backend not responding
///     Copy URL ▸
///     ─────────
///     Manage Apps…              ⌘O
///     Copy Agent Instructions URL ⇧⌘C
///     Open Agent Instructions   ⌘I
///     ─────────
///     Settings…                 ⌘,
///     Quit Subpanel             ⌘Q
///
/// Everything shown comes from the model's last poll; nothing here touches
/// the network while the menu is open.
struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuStatusSection()

        if !model.apps.isEmpty {
            Divider()
            ForEach(model.apps) { app in
                Button(app.name, systemImage: app.reachable == false ? "circle" : "circle.fill") {
                    Desktop.open(app.url)
                }
                .accessibilityLabel(app.reachable == false ? "\(app.name), not responding" : app.name)
            }
            Menu("Copy URL") {
                ForEach(model.apps) { app in
                    Button(app.url) { Desktop.copy(app.url) }
                }
            }
        }

        Divider()
        Button("Manage Apps…", action: showApps)
            .keyboardShortcut("o")
        Button("Copy Agent Instructions URL", action: copyInstructionsURL)
            .keyboardShortcut("c", modifiers: [.command, .shift])
        Button("Open Agent Instructions", action: openInstructions)
            .keyboardShortcut("i")

        Divider()
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Quit Subpanel", action: quit)
            .keyboardShortcut("q")
    }

    private func showApps() {
        openWindow(id: WindowID.apps)
        Desktop.activate()
    }

    private func showSettings() {
        Desktop.activate()
        openSettings()
    }

    private func copyInstructionsURL() {
        Desktop.copy(model.instructionsURL.absoluteString)
    }

    private func openInstructions() {
        Desktop.open(model.instructionsURL)
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
