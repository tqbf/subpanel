# Architecture

## Processes

| Process | Runs as | Started by | Owns |
|---|---|---|---|
| `subpanel-service` | the logged-in user | launchd (LaunchAgent, `KeepAlive`) | port 80 sockets (via launchd), the registry, all routing |
| `SubpanelMenu` (Subpanel Menu) | the logged-in user | login item (`SMAppService.loginItem`) | the menu-bar icon; a client |
| `Subpanel` (Subpanel.app) | the logged-in user | the user, or "Open Subpanel" in the menu | the management window; a client |

All three ship in one bundle:

```
Subpanel.app/Contents/
  MacOS/Subpanel                      SwiftUI Dock app: Apps window + Settings
  MacOS/subpanel-service              the proxy
  Library/LaunchAgents/org.sockpuppet.subpanel.service.plist
  Library/LoginItems/SubpanelMenu.app the menu-bar app (LSUIElement)
```

Subpanel.app registers the plist with `SMAppService.agent(plistName:)` and
the menu app with `SMAppService.loginItem(identifier:)`. Both are done on
first run, and by `make install` through `--install-service` and
`--install-menu`. From then on launchd runs the service at every login and
restarts it if it exits, and the menu app starts at login. Quitting either
app changes nothing about routing. The menu's "Open Subpanel" launches the
enclosing Subpanel.app. Closing Subpanel.app's window quits it.

## Targets

```
SubpanelCore      Foundation only. AppName, BackendTarget, AppMapping,
                  RegistryStore (JSON file), MappingRegistry (actor),
                  RoutingTable + HostRoute, ControlAPI, APIModels (wire DTOs),
                  AgentInstructions, MarkdownHTML, Pages, ProxyProblems.
                  Also ListeningSockets/ListenerIndex (the libproc socket-
                  table scan) and SubpanelClient (the apps' API client).
SubpanelServer    SwiftNIO. ProxyServer (listeners), ProxyHandler (per-
                  connection state machine), BackendHandler, UpgradeGate,
                  GlueHandler, ProxyHeaders, LaunchdSockets.
SubpanelService   main.swift: parse flags, load registry, get sockets, serve.
Subpanel          Subpanel.app (SwiftUI). Depends on SubpanelCore only.
SubpanelMenu      the menu-bar app (SwiftUI MenuBarExtra). SubpanelCore only.
                  Neither app links NIO.
```

`ControlAPI` lives in Core, not Server, because it is a pure
`ControlRequest → LocalResponse` function over the registry: it is tested
without any networking, and the NIO layer just adapts it.

## Data flow

**Register** (`PUT /api/v1/apps/wiki`): NIO buffers the (≤64 KiB) body →
`ControlAPI.handle` validates name + target → `MappingRegistry.put` writes
`registry.json` atomically, *then* commits in memory and publishes a new
`RoutingTable` snapshot → 201/200 JSON.

**Proxy** (`GET http://wiki.localhost/x`): `ProxyHandler` routes by `Host` →
reads `RoutingTable` (a dictionary lookup under a lock) once → connects to the
backend on the same event loop → streams both directions. The registry is never
touched again for that request, so a PUT mid-request only affects new requests.

## Concurrency model

- **`MappingRegistry` is an actor** and the single writer of mapping state.
- **`RoutingTable`** is the read side: an immutable `[name: BackendTarget]`
  snapshot behind an `OSAllocatedUnfairLock`, replaced wholesale on each
  commit. It's the one lock in the design, justified by an API boundary: NIO
  channel handlers route synchronously on their event loop and can't `await`
  an actor.
- **Proxy I/O** is SwiftNIO channel handlers. Client and backend channels for
  one exchange share an event loop, so they call each other synchronously and
  lock-free; cross-loop capture goes through `NIOLoopBound`, and futures are
  consumed with `assumeIsolated()`.
- **Control requests** hop from the event loop into Swift concurrency with
  `EventLoopPromise.completeWithTask` and back.
- **The app** has one `@Observable @MainActor AppModel`; network calls are
  `async` on a `Sendable` client.

## "Listening" without probing

The API's `listening` field and the `listener` process name come from
`ListeningSockets.scan()`, a libproc walk of the user's processes' TCP
sockets in the LISTEN state. That's the data `lsof -iTCP -sTCP:LISTEN`
shows. It takes about 1 ms and is cached for 1 s by `ListenerIndex`.
Nothing ever connects to a backend to check it. (v1 first used a TCP
connect probe. The user asked for none, and a probe can show up in a dev
server's logs.) One limit: it only sees processes owned by the user. See
api.md.

## The app talks HTTP, not XPC (IPC decision)

The plan preferred XPC for UI↔service, falling back to the loopback HTTP API.
We use the HTTP API for everything, because:

- the service has **no privileged operations** (launchd does the one
  privileged thing, binding port 80), so there's nothing that needs a narrow
  authenticated channel;
- service *management* (register/unregister/restart) is done by the app
  itself through `SMAppService` and `launchctl kickstart` on its own agent;
- one API means the UI exercises exactly what agents use.

## Security model (summary — details in api.md)

Loopback only, at every layer: launchd binds 127.0.0.1/::1 (never 0.0.0.0),
the accept path drops non-loopback peers anyway, and targets must be
structurally loopback. The control API answers only on `Host:
subpanel.localhost` (defeats DNS rebinding), sends no CORS headers, and
refuses mutations carrying a foreign `Origin`. No auth: any local process can
change mappings, which is the documented trust model.
