import SwiftUI

/// A small tinted status dot followed by its word, e.g. "● Running". The dot's
/// *shape* (filled vs. hollow, chosen by the caller) carries the state too, so
/// it doesn't depend on color alone. One style for every status in the app.
struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.tightSpacing) {
            configuration.icon
                .font(.system(size: Theme.dotSize))
                .foregroundStyle(tint)
            configuration.title
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
