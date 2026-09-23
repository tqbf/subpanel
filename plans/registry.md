# Registry: data model, validation, persistence

Source: `Sources/SubpanelCore/` — `AppName`, `BackendTarget`, `AppMapping`,
`RegistryStore`, `MappingRegistry`, `RoutingTable`. Tests:
`ValidationTests.swift`, `RegistryTests.swift`.

## Model

```swift
struct AppMapping: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String          // validated AppName
    var targetHost: String    // "127.0.0.1" | "::1" | "localhost"
    var targetPort: Int
    var createdAt: Date
    var updatedAt: Date
}
```

The API exposes the target as a URL string (`http://127.0.0.1:43127`,
`http://[::1]:3000`); internally it's normalized to host + port.

## Names (`AppName`)

- ASCII `a-z`, `0-9`, `-`; must start and end with a letter or digit; 1–63
  bytes; a single label (the caller sends `wiki`, not `wiki.localhost`).
- **Uppercase is rejected, not normalized**, with a hint (`use 'foo'`). The
  alternative, silently lowercasing, would let a caller end up with a mapping
  under a name they didn't send.
- Reserved: `subpanel` (409 `reserved_name`). Add more to
  `SubpanelConstants.reservedNames` *and* to the instructions document.

## Targets (`BackendTarget`)

- `http://` only; https is rejected with an explanation.
- The host must be structurally `127.0.0.1`, `::1`, or `localhost`. Nothing
  is resolved. Anything else gets `non_loopback_target`. This keeps Subpanel
  from becoming a localhost→network SSRF relay.
- The port is required, must be 1–65535, and **can't be 80**. Port 80 is
  Subpanel itself; registering it would create a loop.
- No path, query, fragment, or userinfo. A trailing `/` is fine.
- `localhost` targets connect to both `::1` and `127.0.0.1` (NIO Happy
  Eyeballs). The instructions recommend it for Node servers that bind
  `localhost` to IPv6 only. This is tested.

## Persistence (`RegistryStore`)

`~/Library/Application Support/Subpanel/registry.json`, written only by the
service:

```json
{
  "apps" : [
    { "createdAt" : "…", "id" : "…", "name" : "wiki", "targetHost" : "127.0.0.1",
      "targetPort" : 43127, "updatedAt" : "…" }
  ],
  "version" : 1
}
```

- **Atomic writes** use `Data.write(options: .atomic)` (temp file, then
  rename). Apps are sorted by name, and keys are sorted.
- **Persist first, commit second.** `MappingRegistry.commit` saves, then
  updates memory, then publishes the routing snapshot. If the save fails, the
  API returns 500 and memory and routing stay unchanged.
- **Loaded before traffic.** `subpanel-service` awaits `registry.load()`
  before it binds or adopts any listener.
- **A malformed file is never overwritten.** Bad JSON, an unknown `version`,
  an entry that fails validation, or a duplicate name all trigger the same
  recovery. The file is renamed to `registry.json.unreadable-<timestamp>`,
  the service starts empty, and the reason is surfaced as
  `registryWarning` in `/api/v1/status` and in Settings. If renaming fails,
  the warning says so.
- **Schema version.** Version 1. A future version should migrate forward in
  `RegistryStore.load`. Today an unknown version is set aside, which
  preserves a newer file after a downgrade.

## Reads vs. writes

`MappingRegistry` (an actor) is the only writer. After each commit it
publishes an immutable `[name: BackendTarget]` to `RoutingTable`, which the
proxy reads synchronously. See architecture.md, "Concurrency model".
