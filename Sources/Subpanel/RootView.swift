import SwiftUI

/// The window's root: a two-column `NavigationSplitView` — sidebar of
/// destinations on the left, the selected destination's content on the
/// right. The closed `SidebarSection` set keeps navigation to a plain
/// `List(selection:)` + `switch`, which is the right tool at this size.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarSection? = .reading

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(
                min: Theme.sidebarMinWidth,
                ideal: Theme.sidebarIdealWidth,
                max: Theme.sidebarMaxWidth)
            .navigationTitle("Subpanel")
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .reading:
            ReadingView(document: model.document)
        case .table:
            DataTableView(items: model.items)
        case nil:
            // A selectable sidebar should never rest on a blank canvas
            // (SWIFTUI-RULES §7.1).
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "sidebar.left",
                description: Text("Choose a section in the sidebar to begin."))
        }
    }
}
