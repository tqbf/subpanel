import SubpanelCore
import SwiftUI

/// Picks what the apps window shows: the table, the empty state, or why the
/// service is down.
struct AppsWindowContent: View {
    @Environment(AppModel.self) private var model
    let apps: [AppDTO]
    @Binding var selection: Set<AppDTO.ID>
    let add: () -> Void
    let edit: (AppDTO) -> Void

    var body: some View {
        switch model.health {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notResponding:
            ServiceDownView()
        case .running where model.apps.isEmpty:
            AppsEmptyState(add: add)
        case .running:
            AppsTable(apps: apps, selection: $selection, edit: edit)
        }
    }
}
