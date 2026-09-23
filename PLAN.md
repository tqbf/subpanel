# Subpanel — master plan & index

**Subpanel is a macOS menu-bar app that gives local web apps stable,
human-readable URLs** — `http://wiki.localhost`, `http://phone.localhost` —
by running a loopback reverse proxy on port 80. Coding agents register their
apps over a tiny HTTP API that they discover at one fixed URL:

```sh
curl http://subpanel.localhost/instructions     # or just: curl http://subpanel.localhost/
```

That URL is the product's front door for agents that know nothing about
Subpanel. Everything else in this repo exists to make it true, durably.

Read this file and [PROGRESS.md](PROGRESS.md) and you're up to speed. Depth
lives in `plans/`.

---

## 1. The whole idea in one picture

```
 browser / agent                    Subpanel.app (menu bar; optional)
      │  http://wiki.localhost            │ HTTP API client only
      ▼                                   ▼
 ┌──────────────── subpanel-service (LaunchAgent, runs as you) ──────────────┐
 │ launchd binds 127.0.0.1:80 + [::1]:80 and hands us the sockets            │
 │ Host: subpanel.localhost  → control API, instructions, status page        │
 │ Host: <name>.localhost    → reverse proxy → 127.0.0.1:<port> (streaming,  │
 │                             WebSockets, SSE)                              │
 │ registry: ~/Library/Application Support/Subpanel/registry.json            │
 └───────────────────────────────────────────────────────────────────────────┘
```

- The **service** is the authority. The menu-bar app is a client of its HTTP
  API and can quit without affecting routing.
- **No root, anywhere.** launchd socket activation binds port 80 on behalf of
  an ordinary per-user LaunchAgent ([plans/service-lifecycle.md](plans/service-lifecycle.md)).
- **No DNS, no /etc/hosts, no TLS.** `*.localhost` already resolves to loopback.
- The durable abstraction is `name → loopback HTTP endpoint`. Subpanel never
  launches or supervises apps.

## 2. Status

v1 is built, installed on the dev machine, and verified end to end — see
[PROGRESS.md](PROGRESS.md) for exactly what was tested and what wasn't.

## 3. Where things live

```
Package.swift                 SwiftPM: 4 targets + tests; one dependency (swift-nio, pinned)
Sources/SubpanelCore/         registry, validation, persistence, control API, instructions,
                              HTML pages — Foundation only; shared by everything
Sources/SubpanelServer/       SwiftNIO reverse proxy, launchd socket activation, TCP probe
Sources/SubpanelService/      subpanel-service main.swift (the LaunchAgent executable)
Sources/Subpanel/             SwiftUI menu-bar app (one type per file)
Sources/CLaunch/              module map for <launch.h>
Resources/Info.plist          app bundle metadata (LSUIElement, ATS for *.localhost)
Resources/LaunchAgents/       org.sockpuppet.subpanel.service.plist (Sockets → port 80)
Subpanel/Subpanel.entitlements  not sandboxed (and why)
Tests/SubpanelTests/          swift-testing: unit + real-socket proxy integration
scripts/smoke.sh              end-to-end checks against the installed service (port 80)
scripts/make-icon.swift       draws the app icon
build.sh / Makefile           no-Xcode build → sign → bundle; `make help`
```

## 4. Documentation index

- [plans/architecture.md](plans/architecture.md) — components, processes, data
  flow, concurrency model, why the app talks HTTP instead of XPC.
- [plans/api.md](plans/api.md) — the HTTP API, discovery, the agent
  instructions document, error codes, the local security model.
- [plans/proxy.md](plans/proxy.md) — reverse-proxy semantics: routing,
  headers, streaming/backpressure, upgrades, 404/502/508, limits, and why it's
  SwiftNIO rather than swift-http-server.
- [plans/registry.md](plans/registry.md) — the data model, name and target
  validation, persistence and malformed-file recovery.
- [plans/service-lifecycle.md](plans/service-lifecycle.md) — launchd socket
  activation, SMAppService registration, install/repair, crash recovery,
  development mode.
- [plans/design-system.md](plans/design-system.md) — the menu-bar UI, type
  scale (SwiftUI + HTML pages), macOS idioms, and the snapshot tool for visual
  checks.
- [plans/build-system.md](plans/build-system.md) — `make`, `build.sh`, bundle
  layout, signing, release.
- [plans/testing.md](plans/testing.md) — what's tested where, how to run it,
  and the manual browser/HMR recipe.
- [PROGRESS.md](PROGRESS.md) — running log (newest first).
- [PROBLEMS.md](PROBLEMS.md) — things that bit us; read before changing the
  proxy's state machine or the install flow.
- [SWIFTUI-RULES.md](SWIFTUI-RULES.md) — hard-won SwiftUI rules the UI follows.

## 5. Daily commands

```
make check        compile gate (all targets)
make test         57 tests: unit + proxy integration on real sockets
make run          build + launch build/Subpanel.app
make install      copy to /Applications, (re)register the port-80 service
make smoke        end-to-end checks against the installed service
make service-dev  run the proxy by hand on :8080 (no launchd); pair with
                  SUBPANEL_BASE_URL=http://subpanel.localhost:8080 for the app
```

## 6. The working agreement

`CLAUDE.md` / `AGENTS.md` are the law: drive UI work through the
**swiftui-pro**, **typography-designer** and **macos-design** skills (before
and after), keep this file as the index with depth in `plans/`, log in
`PROGRESS.md`, and never merge to `main` yourself.

## 7. The convention for agents (also in README and /instructions)

> When building a local web application on a machine running Subpanel, bind
> the application to loopback on an available high port, then register a
> stable lowercase name with Subpanel. Treat `http://<name>.localhost` as the
> canonical user-facing local URL. If the backing port changes, update the
> Subpanel mapping. Registration does not launch or supervise the application
> process.
