# Progress

Running log. Append an entry per meaningful change: what you did, what you
learned, what surprised you (`SWIFTUI-RULES.md` §10.1). Newest at the top.

---

## 2026-09-23 — Menu-bar app; "listening" without probing; proxy review fixes

**Menu-bar app (user request).** Split the UI into two apps in one bundle:
- **Subpanel Menu** (`Sources/SubpanelMenu`) is a login item at
  `Contents/Library/LoginItems/SubpanelMenu.app`. It lists the apps, each
  with a native icon + title + subtitle: a filled or hollow dot, then
  `python3.11 · 127.0.0.1:50025` or `Not listening · …`. Click to open;
  "Open Subpanel" launches the full app.
- **Subpanel.app** is now an ordinary Dock app. Its main window is the Apps
  manager, and closing it quits the app. Settings → General toggles the menu
  item. First run registers both. So do `--install-menu` and `make install`.

**No probing.** The user asked for connectivity without probing. The API's
`reachable` field, which came from a TCP-connect probe, is replaced by
`listening` plus `listener {pid, process}`. They come from a libproc scan of
the user's processes' LISTEN sockets (`ListeningSockets`, about 1 ms, cached
1 s): the data `lsof -iTCP -sTCP:LISTEN` shows. Nothing connects to a
backend. The Apps table's Listening column, the HTML status page, the agent
instructions and the menu all use it. Limitation: it only sees the user's
own processes.

**Proxy review.** An adversarial review found and reproduced 10 defects, all
fixed with regression tests (`ProxyRegressionTests.swift`):
- a backend status below 100 crashed the service;
- a reference cycle leaked every exchange;
- the fd limit was 256 and idle connections never closed;
- clients that half-closed got no response;
- a frame sent with a 101 was lost when the backend closed immediately;
- absolute-form requests to the control plane failed;
- a second re-entrancy drop;
- `Connection: Content-Length` let a request be smuggled;
- CONNECT hung;
- `Expect` added a 1 s delay.

**Verified:** 72 tests pass. `make install` from scratch registers both
items: the service is running from /Applications (runs = 1), the menu app
is running, and smoke passes. The real menu was photographed with
`MenuSnapshot`. The main window and Settings were snapshotted.

**Surprises** → PROBLEMS.md:
- A menu subtitle needs `Label` + `Text`, not a second Text inside the
  Label.
- An older installed binary given an unknown flag launched its GUI, whose
  first-run window re-registered the service mid-install. Unknown `--` flags
  now exit 64, and `make install` uses only the new binary.

---

## 2026-09-23 — Breaker-panel icon

At the user's request, replaced the placeholder mark with an **electrical
subpanel** based on their reference artwork: a dark enclosure, a yellow
hazard sign, three breakers, and conduit feet on a light tile. It's redrawn
as vector CoreGraphics in `scripts/make-icon.swift` using the reference's
coordinates. A matching 18 pt template glyph (`MenuBarGlyph.swift`) replaces
the SF Symbol in the menu bar. Checked at 1024 down to 16 px and in the
Welcome window. Lesson: filling a rounded-corner triangle through one
winding-rule clip (the triangle plus its round-join stroke) leaves a seam.
Fill the two regions separately.

---

## 2026-09-23 — Subpanel v1 built, installed, and verified

Built Subpanel from the plan (`subpanel-plan.md`, supplied by the user) on the
Starter template (renamed, fresh `git init`; work on branch `subpanel-v1`).

**What exists**
- `SubpanelCore`: validation, actor registry, atomic JSON persistence with
  malformed-file quarantine, routing snapshot, control API, agent
  instructions (Markdown + tiny HTML renderer), status/404/502 pages.
- `SubpanelServer`: a SwiftNIO reverse proxy. It streams both ways with
  backpressure, handles hop-by-hop headers and X-Forwarded/Forwarded/Via,
  preserves Host, tunnels upgrades through glue handlers, forwards 1xx,
  handles HEAD, HTTP/1.0, absolute-form targets, pipelining, 404/502/508,
  loop detection, and accepts loopback peers only.
- `subpanel-service`: launchd socket activation (port 80 as the user, no
  root), or `--port` for development.
- The menu-bar app: menu, Apps window, tabbed Settings, Welcome, and headless
  `--install-service` / `--uninstall-service` / `--service-status`.
- `make install` / `smoke` / `service-dev`; a `DevSnapshot` visual-check hook;
  a new icon; docs (PLAN.md index + 8 plans).

**Decisions that deviate from the plan (with reasons in plans/)**
- **SwiftNIO directly, not swift-http-server.** Its releases need Swift tools
  6.4 (we have 6.3.3), it can't adopt launchd sockets, and it has no upgrade
  hook (proxy.md).
- **No privileged helper.** A per-user LaunchAgent with launchd `Sockets`
  gets 127.0.0.1:80 and [::1]:80 without root (service-lifecycle.md). This
  is strictly less privilege than the plan's "narrow root helper".
- **The app uses the HTTP API, not XPC.** Nothing is privileged, so there's
  nothing for XPC to protect (architecture.md).
- **macOS 15 minimum** for SwiftUI's `Tab` in Settings.
- **Not sandboxed** (Developer ID tool; see the entitlements file).
- **The port reservation endpoint (§19) isn't implemented.** The plan marked
  it optional. The instructions give agents a bind-port-0 / python one-liner
  approach instead.

**Verified on this machine (macOS 26.5)**
- `make test`: 57 tests pass (unit + real-socket proxy integration).
- Installed at `/Applications/Subpanel.app`. The agent is registered via
  SMAppService, runs as the user from the installed bundle, and listens on
  127.0.0.1:80 and [::1]:80.
- `make smoke`: all 16 port-80 checks pass (IPv4 + IPv6, immediate updates,
  persistence, 502, delete, rejections).
- Headless Chrome through port 80: **Vite 8 HMR** works (WebSocket 101,
  "[vite] hot updated", no reload). fetch POST, cookies, EventSource, and a
  WebSocket echo all work. Host is preserved as `*.localhost`.
- `kill -9` the service: launchd respawned it, a request made in the gap got
  a 200 in about 3 ms, and mappings survived.
- The UI was snapshotted in light and dark, running, down, and empty states.
  A swiftui-pro review was applied: model-driven error alerts, Add can't
  overwrite, text-bound port field, delete confirmation, visible-only
  selection, refresh ordering, VoiceOver on status dots, and more.

**Not verified**
- An actual reboot/logout. The SMAppService registration with `RunAtLoad`
  should cover it, but this session didn't log out.
- Safari automation. (The system resolver does resolve `*.localhost`.)
- `make dist`: no Developer ID identity in this session.

**Surprises** → PROBLEMS.md: pipelining re-entrancy on `.end`; unflushed
post-101 bytes; two app copies confusing BTM (port 80 hung until both
registrations were retired); grouped Forms snapshot blank.

---
> The two entries below are the template's own history (it was called
> "Starter"), kept as the record of where the scaffold came from.

## 2026-06-28 — Metabolized learnings from the first app on this template

Folded `LEARNINGS.md` (general lessons from building the first app — an
outdoor-weather feature — on this scaffold) into the permanent docs, then
deleted the copy. Where each landed:

- `SWIFTUI-RULES.md` **§5.6** — `foregroundStyle` resolves innermost-wins (a
  tinted container can host a differently-colored inline child; the corollary
  bites the "explicit `.foregroundStyle(.primary)`" habit).
- `SWIFTUI-RULES.md` **§11 Swift Charts** (new) — overlaid lines need distinct
  `series:` or they merge into one path; the x-domain is the union of all
  plotted data, so clip overlays to the primary series' window.
- `SWIFTUI-RULES.md` **§12 Concurrency** (new) — a `@MainActor` type adopting a
  delegate protocol needs an isolated conformance (`@MainActor CLLocationManagerDelegate`).
- `plans/build-system.md` — new "Permissions & capabilities" section: usage
  prompts work in this ad-hoc-signed, no-Xcode bundle given the right
  `NS…UsageDescription` keys; the sandbox decides whether a `com.apple.security.*`
  entitlement is also needed; always design the denied path.

Appended §11/§12 rather than renumbering so the existing §9/§10 cross-references
in `PLAN.md` / `PROGRESS.md` stay valid.

## 2026-06-28 — Template scaffold (the "Starter" baseline)

Built the template this repo ships as:

- **Build system** lifted from the Casette app's SwiftPM-only setup and
  generalized: `Package.swift` (one exe + one test target, Swift 6 mode, no
  deps), `build.sh` (swift build → `.app` → codesign, ad-hoc fallback),
  `Makefile` (build/check/test/run/install + sign→notarize→staple→zip `dist`
  pipeline), `Resources/Info.plist`, sandboxed `Starter.entitlements`,
  `scripts/make-icon.swift` (pure-CoreGraphics doc-and-table glyph).
- **App**: `NavigationSplitView` with a `SidebarSection` enum driving a lorem
  reading column (`ReadingView`, measure-capped) and a native sortable `Table`
  (`DataTableView`) with a reusable `StatusBadge` and a footer count. State in
  one `@Observable @MainActor AppModel`; type/metrics centralized in `Theme`.
- **`scripts/rename.sh`** — the meta feature: `cp -R` then one command renames
  target, `.app`, bundle id, dirs, and file contents.
- **Tests**: swift-testing suite covering model load + status sort ordering.
- **Docs**: this file, `PLAN.md` (index, written for the fresh-copy workflow),
  `PROBLEMS.md`, and `plans/{architecture,build-system,design-system,renaming}.md`.

Gates run: `make check` ✓, `make test` ✓ (3 tests), `make build` ✓ (icon +
signed `.app`), live launch ✓ — both destinations render correctly, app stays
alive across a sidebar switch (no constraint crash).

Design work was driven through the macos-design, typography-designer, and
swiftui-pro skills per `CLAUDE.md`, before and after writing the views.
