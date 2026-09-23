import SubpanelCore
import SwiftUI

/// One app in the menu: a status dot, its name, and a subtitle saying who's
/// listening on its target (or that nothing is). Click to open it.
struct AppMenuItem: View {
    let app: AppDTO

    var body: some View {
        // A Label then a second Text is the shape SwiftUI turns into a native
        // menu item with an icon and a subtitle (a second Text *inside* the
        // Label is silently dropped).
        Button(action: open) {
            Label(app.name, systemImage: app.listening == true ? "circle.fill" : "circle")
            Text(detail)
        }
        .accessibilityLabel("\(app.name), \(app.listening == true ? "listening" : "not listening")")
    }

    /// `node · 127.0.0.1:43127`, or `Not listening · 127.0.0.1:5173`.
    private var detail: String {
        let target = app.target.replacing("http://", with: "")
        if app.listening == true {
            return "\(app.listener?.process ?? "Listening") · \(target)"
        }
        return "Not listening · \(target)"
    }

    private func open() {
        if let url = URL(string: app.url) {
            NSWorkspace.shared.open(url)
        }
    }
}
