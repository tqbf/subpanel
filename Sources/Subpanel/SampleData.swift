import Foundation

/// The placeholder content the template ships with. Swap `LoremDocument.demo`
/// and `SampleItem.demo` for your real model; the views don't care where the
/// data comes from.
enum SampleData {}

/// A short structured lorem-ipsum article: a title, a standfirst, and a few
/// headed sections. Structured (not one blob) so the reading column can show
/// a real type hierarchy.
struct LoremDocument {
    struct Section: Identifiable {
        let id = UUID()
        var heading: String
        var body: String
    }

    var title: String
    var lead: String
    var sections: [Section]

    static let demo = LoremDocument(
        title: "Lorem Ipsum",
        lead: "A clean, sandboxed SwiftUI starting point for native macOS apps — "
            + "wired to a no-Xcode SwiftPM build and ready to rename.",
        sections: [
            Section(
                heading: "Dolor sit amet",
                body: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do "
                    + "eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad "
                    + "minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip "
                    + "ex ea commodo consequat. Duis aute irure dolor in reprehenderit in "
                    + "voluptate velit esse cillum dolore eu fugiat nulla pariatur."),
            Section(
                heading: "Consectetur adipiscing",
                body: "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui "
                    + "officia deserunt mollit anim id est laborum. Curabitur pretium tincidunt "
                    + "lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo "
                    + "pharetra, est eros bibendum elit, nec luctus magna felis sollicitudin "
                    + "mauris. Integer in mauris eu nibh euismod gravida."),
            Section(
                heading: "Tempor incididunt",
                body: "Duis ac tellus et risus vulputate vehicula. Donec lobortis risus a "
                    + "elit. Etiam tempor. Ut ullamcorper, ligula eu tempor congue, eros est "
                    + "euismod turpis, id tincidunt sapien risus a quam. Maecenas fermentum "
                    + "consequat mi. Donec fermentum. Pellentesque malesuada nulla a mi."),
        ])
}

extension SampleItem {
    /// A deterministic spread of demo rows that exercises every column type:
    /// text, category, status, a number, and a relative date.
    static let demo: [SampleItem] = {
        let now = Date(timeIntervalSince1970: 1_780_000_000) // fixed → stable previews/tests
        let day: TimeInterval = 86_400
        return [
            SampleItem(name: "Aurora", category: "Design", status: .active, value: 128.50, updated: now - day * 0),
            SampleItem(name: "Borealis", category: "Engineering", status: .active, value: 412.00, updated: now - day * 1),
            SampleItem(name: "Cirrus", category: "Research", status: .paused, value: 76.25, updated: now - day * 3),
            SampleItem(name: "Delta", category: "Design", status: .archived, value: 1024.00, updated: now - day * 9),
            SampleItem(name: "Equinox", category: "Engineering", status: .active, value: 256.75, updated: now - day * 2),
            SampleItem(name: "Fathom", category: "Operations", status: .paused, value: 88.00, updated: now - day * 5),
            SampleItem(name: "Gossamer", category: "Research", status: .active, value: 333.33, updated: now - day * 1),
            SampleItem(name: "Halcyon", category: "Operations", status: .archived, value: 512.10, updated: now - day * 14),
        ]
    }()
}
