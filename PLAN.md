# Subpanel — a clean SwiftUI macOS app template

**You just `cp -R`'d this directory to start a new app. Read this first — it
takes about two minutes, and it's also the master index to everything else.**

This is a deliberately small, modern macOS app you fork by copying. It ships
a real two-pane app (a NavigationSplitView with a lorem-ipsum reading column
and a native sortable `Table`), a no-Xcode SwiftPM build system, and the
conventions/skills wiring that the rest of these docs assume.

---

## 1. The first five minutes (do this in order)

You copied a template named **Subpanel**. Make it yours:

```sh
# 0. From inside your new copy, start a fresh history (the template ships
#    with none of its own — there is nothing to disconnect from).
git init

# 1. Rename everything — target, .app, bundle id, sources, this file's
#    siblings — in one pass. NewName must be a valid Swift identifier.
./scripts/rename.sh NewName                 # bundle id → org.sockpuppet.newname
./scripts/rename.sh NewName com.you.newname # …or pass your own bundle id

# 2. Confirm it still builds and launches as the new app.
make check       # compile-only gate
make run         # build the .app, sign ad-hoc, launch it

# 3. Make these yours by hand (rename.sh leaves them alone on purpose):
#    - VERSION                       → reset to 0.1.0 (it already is)
#    - Resources/Info.plist          → NSHumanReadableCopyright (your name/year)
#    - Resources/Info.plist          → LSApplicationCategoryType (App Store category)
#    - this PLAN.md / README.md      → describe YOUR app, not the template

# 4. Throw away the template's training wheels once you don't need them:
rm scripts/rename.sh        # one-shot; no reason to keep it
# …and start logging YOUR work in PROGRESS.md (see §5).
```

After step 2 you have a running, renamed, ad-hoc-signed macOS app. Everything
below is reference for when you start adding features.

> **Why a rename script instead of placeholders?** A `cp -R` template should
> become a real, differently-named app with one command — not leave you
> find-replacing "Subpanel" across a dozen files and forgetting the bundle id.
> The mechanics live in [plans/renaming.md](plans/renaming.md).

---

## 2. What you're starting from

| Layer            | What's here                                                            |
|------------------|-----------------------------------------------------------------------|
| App              | `NavigationSplitView` → sidebar + (lorem reading column \| `Table`)    |
| State            | one `@Observable @MainActor AppModel`, owned with `@State`            |
| Build            | `swift build` + `build.sh` bundle/sign — **no Xcode project, no xcodebuild** |
| Release          | `make dist`: sign → notarize → staple → zip → checksum                |
| Tests            | swift-testing suite under `Tests/`                                     |
| Conventions      | `CLAUDE.md` / `AGENTS.md`, `SWIFTUI-RULES.md`, three design skills     |

The app is intentionally minimal but *complete* — it's the smallest thing that
still demonstrates the patterns you'll actually reuse (split-view nav, a
centralized type/metrics `Theme`, a reusable badge component, an empty state,
a sortable table, a measure-capped reading column).

---

## 3. Where things live

```
.
├── Package.swift            SwiftPM manifest (one exe target, one test target)
├── Makefile                 the entry point for everything — `make help`
├── build.sh                 swift build → .app bundle → codesign (driven by make)
├── VERSION                  fallback release version (git tag wins over it)
├── Resources/Info.plist     bundle metadata; __VERSION__ placeholders filled at build
├── Subpanel/                 Subpanel.entitlements (sandboxed by default)
├── scripts/
│   ├── make-icon.swift      generates build/AppIcon.icns (pure CoreGraphics)
│   └── rename.sh            the §1 rename tool (delete after use)
├── Sources/Subpanel/         the app (one type per file — see plans/architecture.md)
└── Tests/SubpanelTests/      swift-testing
```

(File and directory names containing "Subpanel" are rewritten by `rename.sh`.)

---

## 4. Documentation index

This file is the index; depth lives in `plans/`. Keep that contract as you
grow — a future agent should be able to read `PLAN.md` + `PROGRESS.md` and be
up to speed (per `CLAUDE.md`).

- [plans/architecture.md](plans/architecture.md) — the app's shape: scenes,
  `AppModel`, navigation, the view tree, how to add a destination.
- [plans/build-system.md](plans/build-system.md) — how `make` / `build.sh`
  turn `swift build` into a signed `.app`, and the release pipeline.
- [plans/design-system.md](plans/design-system.md) — the `Theme` type scale +
  metrics, the macOS idioms applied, and the skills that govern UI work.
- [plans/renaming.md](plans/renaming.md) — what `rename.sh` touches, what it
  deliberately doesn't, and how to rename by hand if you'd rather.
- [PROGRESS.md](PROGRESS.md) — running log; start appending your own entries.
- [PROBLEMS.md](PROBLEMS.md) — "things that bit us" pattern lessons.
- [SWIFTUI-RULES.md](SWIFTUI-RULES.md) — hard-won SwiftUI rules; the code here
  already follows them, and they're cited inline where they apply.

---

## 5. Make targets you'll use daily

```
make check     compile only — the fast agent/CI gate (no bundle, no signing)
make run       build the .app and launch it
make test      run the swift-testing suite
make           build build/Subpanel.app (debug)
make icon      regenerate the app icon from scripts/make-icon.swift
make clean     remove build/ .build/ dist/
make dist      signed + notarized release zip (needs a vX.Y.Z tag + signing identity)
make help      everything else
```

The non-negotiable loop while developing: **`make check` after every change,
`make run` before you trust a UI change.** SwiftUI's compile guarantees are
weak; a passing build is not a passing app (`SWIFTUI-RULES.md` §9).

---

## 6. Adding your own features

- **A new sidebar section:** add a case to `SidebarSection`, give it a title +
  SF Symbol, and add a branch to `RootView.detail`. That's the whole wiring.
- **Real data:** replace `SampleData` / `SampleItem` and point `AppModel` at
  your model. The views take their data as parameters, so they don't care.
- **A dependency:** add it under `dependencies` in `Package.swift` and to the
  `Subpanel` target. If it ships a `*.bundle`, `build.sh` already copies bundles
  into `Contents/Resources` for you.
- **Type & layout:** every font and metric is in `Theme`. Add there, don't
  sprinkle literals (`SWIFTUI-RULES.md` §2.4).

See [plans/architecture.md](plans/architecture.md) for the longer version.

---

## 7. The working agreement (skills & conventions)

`CLAUDE.md` / `AGENTS.md` are the law for agents working in this repo. The
short version, carried over from the template:

- Drive UI work through the **macos-design**, **typography-designer**, and
  **swiftui-pro** skills — before deciding on a design and after writing it.
- Keep this `PLAN.md` as the index; put depth in `plans/`; log in `PROGRESS.md`.
- You may open PRs, but never merge to `main` yourself.

These are good defaults for any app you grow from here — keep them, or adjust
`CLAUDE.md` to match your own workflow.

---

## 8. Before you ship

Distribution is real-signing + notarization, documented in
[plans/build-system.md](plans/build-system.md). The one-time setup:

```sh
make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com   # interactive
git tag v0.1.0 && make dist                                     # sign→notarize→zip
```

`make run` needs none of that — it ad-hoc signs, which is all you need to run
your own app locally.
