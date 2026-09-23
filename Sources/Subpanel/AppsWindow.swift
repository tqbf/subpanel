import SubpanelCore
import SwiftUI

/// "Subpanel Apps": every mapping, with add / edit / delete / open / copy.
/// A single-screen utility window — no sidebar, a sparse toolbar.
struct AppsWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var selection = Set<AppDTO.ID>()
    @State private var search = ""
    @State private var draft: AppDraft?
    @State private var sortOrder = [KeyPathComparator(\AppDTO.name)]
    @State private var pendingDeletion: [String] = []
    @State private var confirmingDeletion = false

    var body: some View {
        AppsWindowContent(
            apps: filteredApps,
            search: search,
            selection: $selection,
            sortOrder: $sortOrder,
            add: add,
            edit: edit,
            delete: confirmDelete
        )
            .frame(minWidth: Theme.appsMinWidth, minHeight: Theme.appsMinHeight)
            .navigationSubtitle(subtitle)
            .searchable(text: $search, placement: .toolbar, prompt: "Filter Apps")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                        .keyboardShortcut("r")
                        .help("Refresh (⌘R)")
                    Button("Delete", systemImage: "trash", action: deleteSelection)
                        .disabled(selection.isEmpty)
                        .help("Delete the selected apps (⌫)")
                    Button("Add App", systemImage: "plus", action: add)
                        .keyboardShortcut("n")
                        .help("Add an app (⌘N)")
                        .disabled(!model.isRunning)
                }
            }
            .onDeleteCommand(perform: deleteSelection)
            .confirmationDialog(deletionTitle, isPresented: $confirmingDeletion) {
                Button("Delete", role: .destructive, action: performDeletion)
            } message: {
                Text("Their URLs will stop working. An agent can register them again.")
            }
            .copyable(selectedApps.map(\.url))
            .sheet(item: $draft) { draft in
                AppEditorSheet(draft: draft)
            }
            .actionErrorAlert()
            .task { await start() }
    }

    private var filteredApps: [AppDTO] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedStandardContains(search) || $0.target.localizedStandardContains(search)
        }
    }

    /// Only rows the user can see: a filter hides rows but not selection.
    private var selectedApps: [AppDTO] {
        filteredApps.filter { selection.contains($0.id) }
    }

    private var deletionTitle: String {
        pendingDeletion.count == 1 ? "Delete “\(pendingDeletion[0])”?" : "Delete \(pendingDeletion.count) apps?"
    }

    private var subtitle: String {
        switch model.health {
        case .running: model.apps.count == 1 ? "1 app" : "\(model.apps.count) apps"
        case .checking: "Connecting…"
        case .notResponding: "Service not running"
        }
    }

    /// The main window opens at launch, so it starts polling and, on the
    /// first run, shows the welcome window.
    private func start() async {
        model.start()
        if DevSnapshot.directory != nil {
            await DevSnapshot.run(openWindow: openWindow, openSettings: openSettings)
        } else if !hasSeenWelcome {
            openWindow(id: WindowID.welcome)
        }
    }

    private func add() {
        draft = .new()
    }

    private func edit(_ app: AppDTO) {
        draft = .editing(app)
    }

    private func refresh() {
        Task { await model.refresh() }
    }

    private func deleteSelection() {
        confirmDelete(selectedApps)
    }

    private func confirmDelete(_ apps: [AppDTO]) {
        guard !apps.isEmpty else { return }
        pendingDeletion = apps.map(\.name)
        confirmingDeletion = true
    }

    private func performDeletion() {
        let names = pendingDeletion
        selection.subtract(names)
        Task { await model.delete(names) }
    }
}
