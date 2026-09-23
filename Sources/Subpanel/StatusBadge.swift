import SwiftUI

/// A small tinted capsule for a `SampleItem.Status`. One component, reused
/// wherever a status renders, so a future tint/shape change lands once
/// (SWIFTUI-RULES §5.4).
struct StatusBadge: View {
    let status: SampleItem.Status

    var body: some View {
        Text(status.rawValue)
            .font(Theme.Fonts.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.badgePaddingHorizontal)
            .padding(.vertical, Theme.badgePaddingVertical)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: Theme.badgeCornerRadius))
            // The color carries meaning, so name it for VoiceOver.
            .accessibilityLabel("Status: \(status.rawValue)")
    }

    private var tint: Color {
        switch status {
        case .active: .green
        case .paused: .orange
        case .archived: .secondary
        }
    }
}
