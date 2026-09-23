import SubpanelCore
import SwiftUI

/// Where the mappings live. Read-only here: the service owns the file.
struct DataSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Data") {
            LabeledContent("Registry") {
                Text((registryPath as NSString).abbreviatingWithTildeInPath)
                    .font(Theme.Fonts.machineDetail)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let warning = model.status?.registryWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Show in Finder", action: reveal)
            }
        }
    }

    private var registryPath: String {
        model.status?.registryPath ?? SubpanelConstants.defaultRegistryURL.path
    }

    private func reveal() {
        let path = registryPath
        if FileManager.default.fileExists(atPath: path) {
            Desktop.reveal(path)
        } else {
            Desktop.open(URL(filePath: path).deletingLastPathComponent())
        }
    }
}
