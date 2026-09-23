# Design system

The UI is governed by three skills (mandated by `CLAUDE.md`): **macos-design**
(layout and idioms), **typography-designer** (type scale), and **swiftui-pro**
(modern API, correctness, review). Run them before *and* after UI work. The
v1 UI was designed with all three, and a swiftui-pro review pass was applied
(PROGRESS.md).

Principle: Subpanel is a **system tool**. The everyday surface is the menu.
Windows appear when needed and are single-screen. No sidebar, sparse toolbars.

## Surfaces

**Menu bar** (`MenuBarExtra`, `.menu` style, so it is a real NSMenu): the
proxy status line and app count; each app as an item (click opens it; a
filled dot means responding, hollow means not); a Copy URL submenu; Manage
Apps… ⌘O; Copy Agent Instructions URL ⇧⌘C; Open Agent Instructions ⌘I;
Settings… ⌘,; Quit ⌘Q. When the service is down, the status section offers
the one relevant fix. The icon is the breaker-panel glyph (see below), or
`exclamationmark.triangle` when the service isn't answering. The menu
shows the model's last poll and never does network work on open.

**Apps window**: a native sortable `Table` with Name, URL, Target, and Status.
- Toolbar: Refresh ⌘R, Delete ⌫, Add ⌘N, and a filter field.
- Double-click opens the app. Rows drag out as URLs. ⌘C copies the selected
  URLs. The context menu has Open, Copy URL, Copy Target, Edit…, and Delete….
- Delete asks for confirmation.
- The window has designed states for empty, no search results, loading, and
  service down (`ContentUnavailableView`).
- The add/edit sheet has Name, Host (127.0.0.1, ::1, or localhost), and Port.
  It validates with the service's own rules before the round trip and won't
  silently replace an existing name.

**Settings**: three toolbar tabs, General / Service / Diagnostics, each a short
grouped form sized to its content, remembering the last tab. No configurable
ports, domains, TLS, or LAN: convention over configuration.

**Welcome** (first run only; closing it any way marks it seen): icon, one
line of explanation, live status, the instructions URL in a code box, and Copy
/ Open / Done. It registers the service if needed.

## Icon and menu-bar glyph

The mark is an **electrical subpanel**, a pun on the name, drawn from the
reference artwork the user supplied. It shows a dark breaker enclosure with a
yellow hazard sign (a dark bolt) and a bank of three breakers, standing on
two conduit feet. The tile is light with a "painted wall" gradient on
Apple's icon grid (824/1024, about 22.4% corners, soft drop shadow).
`scripts/make-icon.swift` redraws it as vector CoreGraphics in the reference's
own coordinate space (1254 px, y-down), so every icon size is crisp. The
only color is the hazard yellow. `make icon` regenerates it.

The **menu-bar glyph** (`MenuBarGlyph.swift`) is the same panel reduced to an
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
| Status | `.body` + secondary, `.caption2` dot | `StatusLabelStyle` (all statuses) |

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
**shape** carries state along with its color: filled means up, hollow means
down, dotted means unknown. It doesn't depend on color alone and reads to
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
