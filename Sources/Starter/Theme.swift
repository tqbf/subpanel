import SwiftUI

/// Centralized layout metrics + type system (SWIFTUI-RULES §2.4, §5.1).
///
/// Two rules keep this honest:
/// - **Scale** comes from semantic SwiftUI text styles only (`.caption` →
///   `.body` → `.title2` → `.largeTitle`), never hardcoded point sizes, so
///   Dynamic Type and OS metric updates keep working.
/// - **Emphasis is weight; de-emphasis is color** (`.secondary` /
///   `.tertiary`), never a lighter font weight.
///
/// When you find yourself typing the same number a third time, it belongs
/// here as a named metric.
enum Theme {
    // MARK: Window
    static let windowMinWidth: CGFloat = 720
    static let windowMinHeight: CGFloat = 480
    static let windowDefaultWidth: CGFloat = 980
    static let windowDefaultHeight: CGFloat = 680

    // MARK: Sidebar
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 240
    static let sidebarMaxWidth: CGFloat = 320

    // MARK: Reading column
    /// Cap the measure so body lines stay near the 60–75 character ideal for
    /// comfortable reading regardless of window width.
    static let readingMaxWidth: CGFloat = 660
    static let readingHorizontalInset: CGFloat = 32
    static let readingTopInset: CGFloat = 28
    static let readingBottomInset: CGFloat = 40
    /// Gap between a section heading and the next.
    static let readingSectionSpacing: CGFloat = 28
    /// Gap between a heading and its body.
    static let readingHeadingSpacing: CGFloat = 8
    /// Extra leading added to body paragraphs for readability.
    static let bodyLineSpacing: CGFloat = 6

    // MARK: Table
    static let badgeCornerRadius: CGFloat = 4
    static let badgePaddingHorizontal: CGFloat = 7
    static let badgePaddingVertical: CGFloat = 2

    // MARK: Type scale
    //
    // The whole app's typography lives here so hierarchy stays consistent and
    // a future restyle lands in one place.
    enum Fonts {
        /// The reading column's page title — the hero.
        static let pageTitle = Font.largeTitle.weight(.bold)
        /// The standfirst/lead under the title — set in a quieter color, not
        /// a lighter weight.
        static let pageLead = Font.title3
        /// A section heading within the reading column.
        static let sectionHeading = Font.title2.weight(.semibold)
        /// Reading body copy.
        static let body = Font.body
        /// Metadata: timestamps, counts, the footer line.
        static let meta = Font.caption

        /// A table cell's primary text.
        static let tableCell = Font.body
        /// Numeric table cells — tabular figures so columns align.
        static let tableNumber = Font.body.monospacedDigit()
        /// The status badge label.
        static let badge = Font.caption.weight(.medium)
    }
}
