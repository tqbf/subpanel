import SwiftUI

/// The proxy's state: "● Running (pid 123)" / "○ Not running" / "Checking…".
struct ServiceStatusLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.health {
        case .checking:
            Text("Checking…")
                .foregroundStyle(.secondary)
        case .running:
            Label(running, systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
        case .notResponding:
            Label("Not running", systemImage: "circle")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        }
    }

    private var running: String {
        model.status.map { "Running (pid \($0.pid))" } ?? "Running"
    }
}
