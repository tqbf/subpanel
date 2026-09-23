import Foundation

/// One row of the demo `Table`. `Identifiable` (not `id:` in the view) per
/// the data-flow guidance, so selection and sorting are stable.
struct SampleItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var category: String
    var status: Status
    var value: Double
    var updated: Date

    /// A small fixed status vocabulary, rendered by `StatusBadge`. Keeping
    /// the tint with the case means every surface shows the same color.
    enum Status: String, CaseIterable, Comparable {
        case active = "Active"
        case paused = "Paused"
        case archived = "Archived"

        /// Sort order for the Status column: most-live first.
        private var rank: Int {
            switch self {
            case .active: 0
            case .paused: 1
            case .archived: 2
            }
        }

        static func < (lhs: Status, rhs: Status) -> Bool {
            lhs.rank < rhs.rank
        }
    }
}
