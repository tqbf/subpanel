import SubpanelCore
import SwiftUI

/// Picks what the apps window shows: the table, an empty or no-results
/// state, or why the service is down.
struct AppsWindowContent: View {
    @Environment(AppModel.self) private var model
    let apps: [AppDTO]
    let search: String
    @Binding var selection: Set<AppDTO.ID>
    @Binding var sortOrder: [KeyPathComparator<AppDTO>]
    let add: () -> Void
    let edit: (AppDTO) -> Void
    let delete: ([AppDTO]) -> Void

    var body: some View {
        switch model.health {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notResponding:
            ServiceDownView()
        case .running where model.apps.isEmpty:
            AppsEmptyState(add: add)
        case .running where apps.isEmpty:
            ContentUnavailableView.search(text: search)
        case .running:
            AppsTable(apps: apps, selection: $selection, sortOrder: $sortOrder, edit: edit, delete: delete)
        }
    }
}
