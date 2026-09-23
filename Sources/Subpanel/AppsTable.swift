import SubpanelCore
import SwiftUI

/// The mappings as a native, sortable table. Double-click opens an app;
/// rows drag out as URLs; right-click for everything else.
struct AppsTable: View {
    @Environment(AppModel.self) private var model
    let apps: [AppDTO]
    @Binding var selection: Set<AppDTO.ID>
    @Binding var sortOrder: [KeyPathComparator<AppDTO>]
    let edit: (AppDTO) -> Void
    let delete: ([AppDTO]) -> Void

    var body: some View {
        Table(of: AppDTO.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { app in
                Text(app.name)
                    .font(Theme.Fonts.appName)
                    .lineLimit(1)
            }
            TableColumn("URL", value: \.url) { app in
                Text(app.url)
                    .font(Theme.Fonts.tableCell)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Target", value: \.target) { app in
                Text(app.target.replacing("http://", with: ""))
                    .font(Theme.Fonts.machineValue)
                    .lineLimit(1)
            }
            TableColumn("Status") { app in
                ReachabilityIndicator(reachable: app.reachable)
            }
        } rows: {
            ForEach(apps.sorted(using: sortOrder)) { app in
                if let url = URL(string: app.url) {
                    TableRow(app).draggable(url)
                } else {
                    TableRow(app)
                }
            }
        }
        .contextMenu(forSelectionType: AppDTO.ID.self) { ids in
            AppActionsMenu(apps: apps.filter { ids.contains($0.id) }, edit: edit, delete: delete)
        } primaryAction: { ids in
            apps.filter { ids.contains($0.id) }.forEach { Desktop.open($0.url) }
        }
    }
}
