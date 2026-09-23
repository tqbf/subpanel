import SwiftUI

/// One settings tab: a grouped form at the settings width. A grouped Form
/// scrolls, so it has no intrinsic height — each tab states the height that
/// fits its content, and the window resizes as you switch tabs.
struct SettingsPane<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(width: Theme.settingsWidth, height: height)
    }
}
