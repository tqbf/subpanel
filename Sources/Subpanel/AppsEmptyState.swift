import SwiftUI

/// No mappings yet: explain where they come from (mostly agents) and offer
/// both ways to get one.
struct AppsEmptyState: View {
    @Environment(AppModel.self) private var model
    let add: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Apps Yet", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Coding agents register apps by following the instructions at \(model.instructionsURL.absoluteString). You can also add one yourself.")
        } actions: {
            Button("Add App", action: add)
            Button("Copy Instructions URL", action: copyInstructionsURL)
        }
    }

    private func copyInstructionsURL() {
        Desktop.copy(model.instructionsURL.absoluteString)
    }
}
