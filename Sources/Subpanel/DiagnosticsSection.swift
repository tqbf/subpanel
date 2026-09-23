import SwiftUI

/// Version, PID, uptime, counts — what you'd want when something's off.
/// The same data is at `/api/v1/status` for scripts.
struct DiagnosticsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Subpanel version", value: appVersion)
            if let status = model.status {
                LabeledContent("Service version", value: status.version)
                LabeledContent("Service PID") {
                    Text(status.pid, format: .number.grouping(.never))
                        .monospacedDigit()
                }
                LabeledContent("Uptime", value: uptime(status.uptimeSeconds))
                LabeledContent("Apps") {
                    Text(status.mappingCount, format: .number)
                        .monospacedDigit()
                }
                LabeledContent("Last registry write") {
                    if let date = status.lastRegistryWrite {
                        Text(date, format: .dateTime)
                    } else {
                        Text("Never")
                    }
                }
            } else {
                LabeledContent("Service", value: "Not responding")
            }
            LabeledContent("Status API") {
                Link(statusURL.absoluteString, destination: statusURL)
                    .font(Theme.Fonts.machineDetail)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private var statusURL: URL {
        model.client.baseURL.appending(path: "api/v1/status")
    }

    private func uptime(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}
