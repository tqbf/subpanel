import SubpanelCore
import SwiftUI

/// Row actions for the apps table's context menu.
struct AppActionsMenu: View {
    let apps: [AppDTO]
    let edit: (AppDTO) -> Void
    /// Asks for confirmation before deleting (owned by the window).
    let delete: ([AppDTO]) -> Void

    var body: some View {
        if let app = apps.first, apps.count == 1 {
            Button("Open in Browser", systemImage: "safari") { Desktop.open(app.url) }
            Button("Copy URL", systemImage: "link") { Desktop.copy(app.url) }
            Button("Copy Target", systemImage: "doc.on.doc") { Desktop.copy(app.target) }
            Divider()
            Button("Edit…", systemImage: "pencil") { edit(app) }
        } else if !apps.isEmpty {
            Button("Open \(apps.count) in Browser", systemImage: "safari", action: openAll)
            Button("Copy URLs", systemImage: "link", action: copyAll)
        }
        if !apps.isEmpty {
            Divider()
            Button(apps.count == 1 ? "Delete…" : "Delete \(apps.count) Apps…", systemImage: "trash", role: .destructive, action: requestDelete)
        }
    }

    private func openAll() {
        apps.forEach { Desktop.open($0.url) }
    }

    private func copyAll() {
        Desktop.copy(apps.map(\.url).joined(separator: "\n"))
    }

    private func requestDelete() {
        delete(apps)
    }
}
