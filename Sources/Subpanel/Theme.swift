import SwiftUI

/// Centralized layout metrics + type system (SWIFTUI-RULES §2.4, §5.1).
///
/// - **Scale** comes from semantic text styles only (macOS: body 13 pt,
///   callout 12, caption 10, title2 17), never hardcoded point sizes.
/// - **Emphasis is weight; de-emphasis is color** (`.secondary`), never a
///   lighter weight.
/// - **Machine values** — URLs, targets, paths, PIDs — are monospaced so they
///   read as things to copy, not prose.
///
/// See plans/design-system.md for the full table.
enum Theme {
    // MARK: Apps window
    static let appsMinWidth: CGFloat = 640
    static let appsMinHeight: CGFloat = 300
    static let appsDefaultWidth: CGFloat = 760
    static let appsDefaultHeight: CGFloat = 420

    // MARK: Sheets, settings, welcome
    static let editorWidth: CGFloat = 380
    static let settingsWidth: CGFloat = 500
    // Per-tab heights that fit each tab's rows without scrolling. (A registry
    // warning can make General taller; the form scrolls then.)
    static let settingsGeneralHeight: CGFloat = 300
    static let settingsServiceHeight: CGFloat = 220
    static let settingsDiagnosticsHeight: CGFloat = 340
    static let welcomeWidth: CGFloat = 440
    static let welcomePadding: CGFloat = 28
    static let welcomeIconSize: CGFloat = 64
    static let stackSpacing: CGFloat = 16
    static let tightSpacing: CGFloat = 6
    static let codeBoxPadding: CGFloat = 10
    static let codeBoxCornerRadius: CGFloat = 8

    enum Fonts {
        /// An app's name — the row's identity, so it carries the weight.
        static let appName = Font.body.weight(.medium)
        /// Ordinary table text.
        static let tableCell = Font.body
        /// Targets and other host:port values — aligned figures.
        static let machineValue = Font.body.monospaced()
        /// Small machine values in forms (paths, listener addresses).
        static let machineDetail = Font.callout.monospaced()
        /// The welcome window's title.
        static let welcomeTitle = Font.title2.weight(.semibold)
        /// The welcome window's explanatory line (set in `.secondary`).
        static let lead = Font.body
        /// Labels above a value, e.g. "Agent instructions".
        static let label = Font.callout.weight(.medium)
        /// Footnotes and hints (set in `.secondary`).
        static let meta = Font.callout
    }
}
