import SubpanelCore
import SwiftUI

/// "Subpanel Apps": every mapping, with add / edit / delete / open / copy.
/// A single-screen utility window — no sidebar, a sparse toolbar.
struct AppsWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<AppDTO.ID>()
    @State private var search = ""
    @State private var draft: AppDraft?
    @State private var showingError = false

    var body: some View {
        AppsWindowContent(apps: filteredApps, selection: $selection, add: add, edit: edit)
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
            .copyable(selectedApps.map(\.url))
            .sheet(item: $draft) { draft in
                AppEditorSheet(draft: draft)
            }
            .alert("Something Went Wrong", isPresented: $showingError) {
                Button("OK", action: clearError)
            } message: {
                Text(model.actionError ?? "")
            }
            .onChange(of: model.actionError) { _, error in
                showingError = error != nil
            }
            .task { await model.refresh() }
    }

    private var filteredApps: [AppDTO] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedStandardContains(search) || $0.target.localizedStandardContains(search)
        }
    }

    private var selectedApps: [AppDTO] {
        model.apps.filter { selection.contains($0.id) }
    }

    private var subtitle: String {
        switch model.health {
        case .running: model.apps.count == 1 ? "1 app" : "\(model.apps.count) apps"
        case .checking: "Connecting…"
        case .notResponding: "Service not running"
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
        let names = selectedApps.map(\.name)
        selection.removeAll()
        Task { await model.delete(names) }
    }

    private func clearError() {
        model.actionError = nil
    }
}
