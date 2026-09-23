import SwiftUI

/// A small tinted status dot followed by its word, e.g. "● Running". The dot's
/// *shape* (filled vs. hollow, chosen by the caller) carries the state too, so
/// it doesn't depend on color alone. One style for every status in the app.
struct StatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.tightSpacing) {
            configuration.icon
                .font(.caption2)
                .imageScale(.small)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            configuration.title
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
