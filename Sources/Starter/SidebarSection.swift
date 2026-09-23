import SwiftUI

/// The sidebar's navigation destinations. A small, closed set, so a plain
/// enum drives both the sidebar list and the detail switch — no
/// `navigationDestination(for:)` plumbing needed at this size.
enum SidebarSection: String, CaseIterable, Identifiable {
    case reading = "Reading"
    case table = "Table"

    var id: Self { self }

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .reading: "doc.text"
        case .table: "tablecells"
        }
    }
}
