# Architecture

The app is small on purpose. This is the whole shape.

## Scene & state ownership

`SubpanelApp` (`@main`) owns exactly one piece of state — the `AppModel` — with
`@State`, and injects it via `.environment(model)`. Everything downstream reads
it with `@Environment(AppModel.self)`. This is the modern Observation flow
(`@Observable` + `@State` for ownership + `@Environment` for passing); there is
no `ObservableObject`/`@Published`/`@StateObject` anywhere, and adding real
mutating state later is a drop-in.

`AppModel` is `@Observable @MainActor`. It currently just holds the demo
content (`document`, `items`), but it's the seam where a store, networking, or
persistence belongs.

## Navigation

`RootView` is a two-column `NavigationSplitView`:

- **Sidebar** — `List(SidebarSection.allCases, selection:)`. `SidebarSection`
  is a small closed enum (`.reading`, `.table`), so navigation is a plain
  `List(selection:)` + a `switch` in the detail builder. We deliberately do
  **not** reach for `navigationDestination(for:)` — that's for open-ended,
  value-driven stacks, not a fixed two-item sidebar.
- **Detail** — `switch selection { … }`, with a `ContentUnavailableView` for
  the `nil` case so a deselected sidebar never shows blank canvas
  (`SWIFTUI-RULES.md` §7.1).

### Adding a destination

1. Add a case to `SidebarSection` with a `title` and an SF Symbol.
2. Add a `case` to `RootView.detail` returning your view.

The sidebar list and the icon come for free from `CaseIterable`.

## View tree

```
SubpanelApp                        WindowGroup + AppModel ownership
└── RootView                      NavigationSplitView (sidebar | detail)
    ├── ReadingView               measure-capped lorem column (title/lead/sections)
    └── DataTableView             native sortable Table
        └── StatusBadge           reusable tinted status capsule
```

Each type is in its own file (`swiftui-pro` convention). Views take their data
as parameters (`ReadingView(document:)`, `DataTableView(items:)`) rather than
reaching into the environment, so they're trivially previewable and reusable.

## Data model

- `SampleItem` — `Identifiable, Hashable` row; conforms via a real `id`, not
  `id:` keypaths in the view (data-flow guidance). Its `Status` enum is
  `Comparable` so the Status column sorts "most live first".
- `SampleData` / `LoremDocument` — the placeholder content. Fixed timestamps so
  previews and tests are deterministic. This is the first thing you replace.

## Concurrency

Swift 6 language mode with strict concurrency is on from day one
(`Package.swift`). `AppModel` is `@MainActor`; the test suite is `@MainActor`
to touch it. Starting strict is cheaper than retrofitting.
