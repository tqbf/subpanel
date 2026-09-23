# Build system

No Xcode project, no `xcodebuild`, no XcodeGen. `swift build` compiles; a shell
script bundles and signs; `make` orchestrates. Xcode is only a toolchain
provider (`swift`, `codesign`, `notarytool`, `stapler`).

## The pieces

- **`Package.swift`**: targets `SubpanelCore`, `SubpanelServer`,
  `SubpanelService` (product `subpanel-service`), `Subpanel` (the app), the
  `CLaunch` system-library module for `<launch.h>`, and `SubpanelTests`.
  Swift 6 language mode, **macOS 15** minimum (for SwiftUI's `Tab`). One
  dependency: `swift-nio`, pinned `exact: "2.103.0"`, with `Package.resolved`
  committed.
- **`build.sh`**: `swift build` builds both executables, then assembles
  `build/Subpanel.app`:
  ```
  Contents/MacOS/Subpanel               the menu-bar app
  Contents/MacOS/subpanel-service       the proxy (BundleProgram of the agent)
  Contents/Library/LaunchAgents/org.sockpuppet.subpanel.service.plist
  Contents/Resources/                   icon, swift-nio_NIOPosix.bundle
  Contents/Info.plist                   version placeholders filled in
  ```
  It then signs **inside-out**: the service with identifier
  `org.sockpuppet.subpanel.service`, then the bundle. It falls back to ad-hoc
  (`-`), which is enough for SMAppService on your own machine.
- **`Makefile`** is the front door. `make help` lists everything.
- **`Resources/Info.plist`** sets `LSUIElement` (menu bar only, no Dock icon),
  the developer-tools category, and an ATS exception so the app can use
  plain HTTP to `*.localhost`.
- **`Resources/LaunchAgents/…plist`** is the service definition
  (service-lifecycle.md).
- **`Subpanel/Subpanel.entitlements`**: App Sandbox is **off**. Subpanel is a
  Developer ID developer tool. The app runs `launchctl kickstart` on its own
  agent and reveals Application Support. The service needs its own
  Application Support directory and launchd-activated sockets. The file
  documents this.

## Permissions & capabilities

OS capabilities work in this no-Xcode, ad-hoc-signed bundle — you just have to
add the keys by hand, because there's no Xcode "Signing & Capabilities" tab
doing it for you:

- **Usage prompts** need the matching `NS…UsageDescription` string in
  `Resources/Info.plist`. CoreLocation, for example, prompts and returns a fix
  with `NSLocationUsageDescription` (+ `NSLocationWhenInUseUsageDescription`)
  present — ad-hoc signing and the hand-assembled `.app` are not a barrier.
- **The sandbox decides the entitlement.** With the App Sandbox **off**, a
  usage-description string is enough. With it **on**, also add the matching
  `com.apple.security.*` entitlement (e.g.
  `com.apple.security.personal-information.location`).
- **Always design the denied path.** A permission the user declines should
  route to a sensible default, not a dead feature — e.g. a one-shot location
  request that yields `nil` falls back to a configured location.

## Everyday targets

| Target        | What it does                                              |
|---------------|----------------------------------------------------------|
| `make check`  | `swift build` only — fast compile gate for CI/agents      |
| `make test`   | `swift test` (swift-testing)                              |
| `make run`    | build the `.app`, ad-hoc sign, `open` it                 |
| `make` / build| `build/Subpanel.app` (debug)                              |
| `make icon`   | regenerate `build/AppIcon.icns`                          |
| `make clean`  | remove `build/ .build/ dist/`                            |
| `make install`| copy to /Applications, retire old registrations, `--install-service` |
| `make uninstall` | `--uninstall-service`, remove /Applications/Subpanel.app |
| `make smoke`  | `scripts/smoke.sh` against the installed service (port 80) |
| `make service-dev` | run the proxy by hand on :8080 with a scratch registry |

## Versioning

`make` resolves the version in this order: a `VERSION=` override → an exact
`vX.Y.Z` git tag at HEAD → the `VERSION` file. `make print-version` shows what
resolved and from where.

## Release pipeline (`make dist`)

Requires an exact `vX.Y.Z` tag at HEAD and a Developer ID signing identity.
The chain is deliberately ordered:

```
clean → release → sign → zip-notary → notarize → staple → zip-release → checksum → verify-release
```

`make sign` signs `Contents/MacOS/subpanel-service` with the hardened runtime
first, then the app. Both need no runtime exceptions. The two-zip dance is intentional: Apple's notary service takes a zip; stapling
writes the ticket back into the `.app`; the zip you actually ship must be made
**after** stapling. One-time credential setup:

```sh
make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com
```

`make github-release` uploads the release zip + `.sha256` to a GitHub release.

## CI gate

The minimum a change must pass: `make check && make test`. The minimum a *UI*
change must pass: also `make run` and look at it — see `SWIFTUI-RULES.md` §9.
