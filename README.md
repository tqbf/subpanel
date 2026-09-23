# Subpanel

A clean, modern **SwiftUI macOS app template** you fork by copying. It's the
smallest thing that still demonstrates the patterns you actually reuse:

- A two-column `NavigationSplitView` — a sidebar driving a measure-capped
  lorem-ipsum reading column and a native, sortable `Table`.
- One `@Observable @MainActor` model, a centralized `Theme` type/metrics
  system, a reusable status badge, and a designed empty state.
- A **no-Xcode** SwiftPM build: `swift build` + `build.sh` produce a signed
  `.app`; `make dist` does the full sign → notarize → staple → zip release.
- Swift 6 strict concurrency, macOS 14+, zero third-party dependencies.

## Quick start

```sh
cp -R swiftui-app MyApp && cd MyApp
git init
./scripts/rename.sh MyApp        # rename target/.app/bundle id/sources in one pass
make run                         # build + launch
```

Then read **[PLAN.md](PLAN.md)** — it's the two-minute onboarding for a fresh
copy and the index to everything else (`plans/`, `PROGRESS.md`, `PROBLEMS.md`,
`SWIFTUI-RULES.md`).

## Make targets

```
make check   compile-only gate        make run    build + launch
make test    run the test suite       make dist   signed release zip
make help    everything else
```

Requires macOS 14+ and a Swift 6 toolchain (Xcode or swift.org). `make run`
ad-hoc signs, so it works on a bare machine with no certificates.
