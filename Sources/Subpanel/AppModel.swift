import Observation

/// App-wide state. The template's data is static demo content, but it lives
/// in an `@Observable @MainActor` class — owned by the app with `@State`,
/// passed down with `@Environment` — so adding real, mutating state later is
/// a drop-in, not a rewrite (data-flow guidance).
@Observable
@MainActor
final class AppModel {
    /// The article shown in the Reading destination.
    var document: LoremDocument

    /// The rows shown in the Table destination.
    var items: [SampleItem]

    init(
        document: LoremDocument = .demo,
        items: [SampleItem] = SampleItem.demo
    ) {
        self.document = document
        self.items = items
    }
}
