import AppKit

/// The handful of AppKit side effects the UI needs: open in the browser,
/// copy, reveal in Finder, bring the app forward.
@MainActor
enum Desktop {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func open(_ string: String) {
        if let url = URL(string: string) {
            open(url)
        }
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    /// A menu-bar (LSUIElement) app has to pull its windows to the front
    /// explicitly, or they open behind whatever the user was doing.
    static func activate() {
        NSApp.activate()
    }
}
