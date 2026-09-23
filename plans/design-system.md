# Design system

The UI is governed by three skills (mandated by `CLAUDE.md`): **macos-design**
(layout and idioms), **typography-designer** (type scale), and **swiftui-pro**
(modern API, correctness, review). Run them before *and* after UI work. The
v1 UI was designed with all three, and a swiftui-pro review pass was applied
(PROGRESS.md).

Principle: Subpanel is a **system tool**. The everyday surface is the menu.
Windows appear when needed and are single-screen. No sidebar, sparse toolbars.

## Surfaces

Two apps, one bundle (architecture.md).

**Subpanel Menu, the menu-bar app** (`Sources/SubpanelMenu`, a `.menu`-style
`MenuBarExtra`, so it's a real NSMenu). It's deliberately minimal, per the
user's brief: current apps, which ones have something listening, and a way
into the full app.

    Apps                                   ← section header
    ● docs      python3.11 · 127.0.0.1:50025
    ○ phone     Not listening · 127.0.0.1:50032
    ─────
    Open Subpanel                     ⌘O
    ─────
    Quit Subpanel Menu                ⌘Q

- Each item is a native icon + title + **subtitle**. The dot is filled when a
  process is listening on the app's port and hollow when nothing is. It's
  read from the OS socket table and never probed. The subtitle names the
  process and the target.
- Clicking an item opens its `.localhost` URL. "Open Subpanel" launches the
  enclosing Subpanel.app.
- SwiftUI shape that yields a subtitle: `Button { Label(name, systemImage:);
  Text(detail) }`. A second `Text` *inside* the Label is silently dropped
  (PROBLEMS.md).
- It shows the last 4-second poll and does no work when opened.

**Subpanel.app, the full app** (`Sources/Subpanel`): an ordinary Dock app.
Closing its window quits it.
- **Main window "Subpanel"**: a native sortable `Table` with Name, URL,
  Target, and Listening (`● python3.11` / `○ Not listening`).
  - Toolbar: Refresh ⌘R, Delete ⌫, Add ⌘N, and a filter field.
  - Double-click opens the app. Rows drag out as URLs. ⌘C copies the selected
    URLs. The context menu has Open, Copy URL, Copy Target, Edit…, and
    Delete….
  - Delete asks for confirmation.
  - Designed states for empty, no search results, loading, and service down
    (`ContentUnavailableView`).
  - The add/edit sheet has Name, Host (127.0.0.1, ::1, or localhost), and
    Port. It validates with the service's own rules and won't silently
    replace an existing name.
- **Settings**: three toolbar tabs, General / Service / Diagnostics, each a
  short grouped form sized to its content, remembering the last tab. General
  has "Show Subpanel in the menu bar" (the menu app's login item) and the
  registry location. There are no configurable ports, domains, TLS, or LAN
  settings: convention over configuration.
- **Welcome** (first run only; closing it any way marks it seen): icon, one
  line of explanation, live status, the instructions URL, and Copy / Open /
  Done. It registers the service and the menu-bar item if needed.

## Icon and menu-bar glyph

The mark is an **electrical subpanel**, a pun on the name, drawn from the
reference artwork the user supplied. It shows a dark breaker enclosure with a
yellow hazard sign (a dark bolt) and a bank of three breakers, standing on
two conduit feet. The tile is light with a "painted wall" gradient on
Apple's icon grid (824/1024, about 22.4% corners, soft drop shadow).
`scripts/make-icon.swift` redraws it as vector CoreGraphics in the reference's
own coordinate space (1254 px, y-down), so every icon size is crisp. The
only color is the hazard yellow. `make icon` regenerates it.

The **menu-bar glyph** (`SubpanelMenu/MenuBarGlyph.swift`) is the same panel reduced to an
18 pt monochrome **template** silhouette: the bolt and breaker well are cut
out, with three breakers and two feet. macOS tints it for light, dark, and
highlighted menu bars. When the service isn't answering, the menu bar shows
`exclamationmark.triangle` instead. Keep the two drawings in step when either
changes.

## Type scale — SwiftUI (`Theme.Fonts`)

macOS text styles: body 13 pt, callout 12, caption 10, title2 17. Emphasis
comes from weight; de-emphasis comes from `.secondary` color, never a lighter
weight. Machine values are monospaced so they read as things to copy.

| Role | Style | Used by |
|---|---|---|
| Window title (Welcome) | `.title2` semibold | "Welcome to Subpanel" |
| Lead | `.body` + secondary | Welcome explanation |
| App name | `.body` medium | Table Name column (the row's identity) |
| Table cell | `.body` | URL column |
| Machine value | `.body` monospaced | Target column, instructions code box |
| Machine detail | `.callout` monospaced | registry path, listeners, status API link |
| Label | `.callout` medium | "Agent instructions" |
| Meta | `.callout` + secondary | hints and footnotes |
| Status | `.body` + secondary, `.caption2` dot | `StatusLabelStyle` (service status, Listening column) |

## Type scale — HTML pages (`Pages.swift`)

Server-rendered for browsers: the status page, rendered instructions, and
404/502/508. System font stack, one accent color, light and dark via
`prefers-color-scheme`, measure capped at 44 rem.

| Role | Size / weight / line-height |
|---|---|
| body | 16px / 400 / 1.55 |
| h1 | 28px / 600 / 1.2, −0.01em |
| h2 | 20px / 600 / 1.3 |
| h3 | 17px / 600 / 1.4 |
| meta, table headers | 14px, secondary color |
| code | 0.875em mono inline; 13px in blocks |

## Status vocabulary

One component, `StatusLabelStyle`: a small dot plus a word. The dot's
**shape** carries state along with its color: filled means up or listening,
hollow means down or not listening, dotted means unknown. The menu uses the
same filled and hollow dots as monochrome menu icons. It doesn't depend on color alone and reads to
VoiceOver as one element. The HTML status page uses the same
filled/hollow dots.

## Visual checks from an agent shell

Screen Recording permission isn't available to agents, so the app can
photograph itself:

```sh
make build
SUBPANEL_SNAPSHOT_DIR=/tmp/shots build/Subpanel.app/Contents/MacOS/Subpanel [-settingsTab service]
SUBPANEL_SNAPSHOT_APPEARANCE=dark …                       # dark mode
SUBPANEL_BASE_URL=http://subpanel.localhost:9 …           # "service down" states
```

`DevSnapshot` opens every window, captures each **own** window through the
window server (`CGWindowListCreateImage`, looked up with `dlsym`, since Swift
marks it unavailable), writes PNGs, and quits. Don't use `cacheDisplay` or
`CALayer.render`: both draw grouped `Form`s blank (PROBLEMS.md).

The menu can be photographed the same way:

```sh
SUBPANEL_SNAPSHOT_DIR=/tmp/menu build/Subpanel.app/Contents/Library/LoginItems/SubpanelMenu.app/Contents/MacOS/SubpanelMenu
```

`MenuSnapshot` waits for a poll, clicks its own status item (the menu opens
in a modal tracking loop), captures its largest own window from a timer
scheduled in `.common` mode, writes `menu.png`, and exits. The menu follows
the menu bar's appearance, not the app's, so there's no separate dark
render.
