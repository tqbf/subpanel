import SwiftUI

/// Is the service installed, is it running, where is it listening — and the
/// two repair actions.
struct ServiceSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Status") {
                ServiceStatusLabel()
            }
            LabeledContent("Login item") {
                LoginItemLabel()
            }
            LabeledContent("Listening on") {
                Text(listeners)
                    .font(Theme.Fonts.machineDetail)
                    .textSelection(.enabled)
            }
            HStack {
                if model.isChangingService {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Restart Service", action: restart)
                    .disabled(model.registration != .enabled || model.isChangingService)
                Button("Reinstall Service", action: reinstall)
                    .disabled(model.isChangingService)
            }
        }
    }

    private var listeners: String {
        model.status?.listeners.joined(separator: ", ") ?? "127.0.0.1:80, [::1]:80"
    }

    private func restart() {
        Task { await model.restartService() }
    }

    private func reinstall() {
        Task { await model.repairService() }
    }
}
