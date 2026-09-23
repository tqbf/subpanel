import SwiftUI

/// A backend's reachability: "● Responding" / "○ Not responding", or
/// "◌ Unknown" when the service didn't probe it.
struct ReachabilityIndicator: View {
    let reachable: Bool?

    var body: some View {
        switch reachable {
        case true?:
            Label("Responding", systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
        case false?:
            Label("Not responding", systemImage: "circle")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        case nil:
            Label("Unknown", systemImage: "circle.dotted")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        }
    }
}
