import SubpanelCore
import SwiftUI

/// Whether a process is listening on an app's target: "● node",
/// "○ Not listening", or "◌ Unknown" when the service didn't check.
struct ListeningIndicator: View {
    let app: AppDTO

    var body: some View {
        switch app.listening {
        case true?:
            Label(app.listener?.process ?? "Listening", systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
                .help(app.listener.map { "\($0.process) (pid \($0.pid)) is listening on \(app.target)" } ?? "")
        case false?:
            Label("Not listening", systemImage: "circle")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        case nil:
            Label("Unknown", systemImage: "circle.dotted")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        }
    }
}
