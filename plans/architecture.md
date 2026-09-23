# Architecture

## Processes

| Process | Runs as | Started by | Owns |
|---|---|---|---|
| `subpanel-service` | the logged-in user | launchd (LaunchAgent, `KeepAlive`) | port 80 sockets (via launchd), the registry, all routing |
| `Subpanel` (menu-bar app) | the logged-in user | the user / login item (optional) | nothing — it's a client |

Both executables ship in one bundle:

```
Subpanel.app/Contents/
  MacOS/Subpanel                      SwiftUI menu-bar app (LSUIElement)
  MacOS/subpanel-service              the proxy
  Library/LaunchAgents/org.sockpuppet.subpanel.service.plist
```

The app registers that plist with `SMAppService.agent(plistName:)`. From then
on launchd runs the service at every login and restarts it if it exits;
quitting (or never opening) the app changes nothing about routing.

## Targets

```
SubpanelCore      Foundation only. AppName, BackendTarget, AppMapping,
                  RegistryStore (JSON file), MappingRegistry (actor),
                  RoutingTable + HostRoute, ControlAPI, APIModels (wire DTOs),
                  AgentInstructions, MarkdownHTML, Pages, ProxyProblems.
SubpanelServer    SwiftNIO. ProxyServer (listeners), ProxyHandler (per-
                  connection state machine), BackendHandler, GlueHandler,
                  ProxyHeaders, LaunchdSockets, TCPReachabilityProber.
SubpanelService   main.swift: parse flags, load registry, get sockets, serve.
Subpanel          the SwiftUI app. Depends on SubpanelCore only (for DTOs and
                  constants) — no NIO in the app binary.
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
