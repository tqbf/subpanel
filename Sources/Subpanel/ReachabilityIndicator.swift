import SwiftUI

/// A backend's reachability: "● Responding" / "○ Not responding".
struct ReachabilityIndicator: View {
    let reachable: Bool?

    var body: some View {
        if reachable == false {
            Label("Not responding", systemImage: "circle")
                .labelStyle(StatusLabelStyle(tint: .secondary))
        } else {
            Label("Responding", systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(tint: .green))
        }
    }
}
