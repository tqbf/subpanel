import Testing
@testable import Starter

@MainActor
struct AppModelTests {
    @Test func defaultModelLoadsDemoContent() {
        let model = AppModel()
        #expect(model.document.title == "Lorem Ipsum")
        #expect(model.document.sections.count == 3)
        #expect(model.items.count == 8)
    }

    @Test func statusSortsMostLiveFirst() {
        #expect(SampleItem.Status.active < .paused)
        #expect(SampleItem.Status.paused < .archived)
        #expect([SampleItem.Status.archived, .active, .paused].sorted()
            == [.active, .paused, .archived])
    }

    @Test func itemsSortByValueDescending() {
        let model = AppModel()
        let sorted = model.items.sorted { $0.value > $1.value }
        #expect(sorted.first?.value == model.items.map(\.value).max())
    }
}
