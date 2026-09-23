import SubpanelCore
import SwiftUI

/// Add or edit one mapping: a name and a loopback port.
struct AppEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppDraft
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(draft: AppDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("myapp"))
                        .disabled(!draft.isNew)
                    LabeledContent("URL") {
                        Text(SubpanelConstants.appURL(name: draft.name.isEmpty ? "name" : draft.name))
                            .font(Theme.Fonts.machineDetail)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(draft.isNew ? "Add App" : "Edit \(draft.name)")
                        .font(.headline)
                }
                Section {
                    Picker("Host", selection: $draft.host) {
                        ForEach(LoopbackHost.allCases) { host in
                            Text(host.label).tag(host)
                        }
                    }
                    TextField("Port", text: $draft.portText, prompt: Text("5173"))
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave || isSaving)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: Theme.editorWidth)
    }

    private func cancel() {
        dismiss()
    }

    private func save() {
        // PUT creates *or replaces*; don't let "Add" silently repoint an app
        // an agent registered.
        if draft.isNew, model.app(named: draft.name) != nil {
            errorMessage = "An app named “\(draft.name)” already exists. Edit it instead."
            return
        }
        let target: String
        do {
            target = try draft.validatedTarget()
        } catch {
            errorMessage = (error as? SubpanelError)?.message ?? error.localizedDescription
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.save(name: draft.name, target: target)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
