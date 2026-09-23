# HTTP API, discovery, and agent instructions

Everything below is served only on `Host: subpanel.localhost` (port 80 in
production; `subpanel.localhost:8080` under `make service-dev`). Source:
`Sources/SubpanelCore/ControlAPI.swift`, `AgentInstructions.swift`,
`APIModels.swift`. Tests: `Tests/SubpanelTests/ControlAPITests.swift`.

## Documents

| Path | Returns |
|---|---|
| `/` | Browsers (`Accept` has `text/html`, not `text/markdown`): the HTML status page (apps + reachability + pointer to instructions). Everyone else (curl's `*/*`, agent fetchers asking for Markdown): **the Markdown instructions**. So "go to subpanel.localhost" works for an agent with no path. |
| `/instructions` | Markdown (`text/markdown; charset=utf-8`), or the same rendered as HTML for browsers |
| `/instructions.md`, `/llms.txt` | Always Markdown |
| `/.well-known/subpanel` | Capability document (JSON) — what future clients should inspect |

The instructions are generated per port (`AgentInstructions.markdown(port:)`),
so every URL in them is right under `make service-dev` too. The first
screenful is sufficient to act; the rest is reference. **Edit the document in
`AgentInstructions.swift` and keep this file in sync.** It contains the
convention paragraph verbatim (`AgentInstructions.convention`), which a test
asserts.

HTML rendering uses `MarkdownHTML`, a deliberately tiny renderer for the
subset the instructions use (headings, paragraphs, lists incl. numbered with
`start`, fenced code, blockquote, inline code/bold/links/autolinks). It is not
a general Markdown engine; if you add syntax to the instructions, check
`MarkdownHTMLTests.rendersTheRealInstructions`.

## Discovery document

```json
{
  "api": "http://subpanel.localhost/api/v1",
  "instructions": "http://subpanel.localhost/instructions",
  "name": "Subpanel",
  "serviceVersion": "0.1.0",
  "supports": { "http": true, "https": false, "websocket": true },
  "version": 1
}
```

## JSON API — `/api/v1`

All responses are pretty-printed JSON with sorted keys. No auth.

| Method & path | Success | Notes |
|---|---|---|
| `GET /api/v1/apps` | 200 `{"apps":[APP…]}` | sorted by name |
| `GET /api/v1/apps/NAME` | 200 APP | 404 `mapping_not_found` |
| `PUT /api/v1/apps/NAME` | **201** APP (created) / **200** APP (updated or unchanged) | body `{"target":"http://127.0.0.1:PORT"}`; idempotent; re-PUT of the same target doesn't touch disk |
| `DELETE /api/v1/apps/NAME` | **204 always** | idempotent: absent and present both 204 (chosen so automation never branches) |
| `GET /api/v1/status` | 200 STATUS | |
| `HEAD` on any GET route | same headers, no body | |

**APP**

```json
{ "name": "wiki", "reachable": true, "target": "http://127.0.0.1:43127", "url": "http://wiki.localhost" }
```

`reachable` is advisory: a TCP connect to the target, cached 2 s
(`TCPReachabilityProber`). Routing never consults it; a down backend keeps its
mapping.

**STATUS**

```json
{
  "apiVersion": 1, "lastRegistryWrite": "2026-09-23T21:02:11Z",
  "listeners": ["127.0.0.1:80", "[::1]:80"], "mappingCount": 3, "pid": 91544,
  "registryPath": "/Users/…/Library/Application Support/Subpanel/registry.json",
  "registryWarning": null, "startedAt": "…", "status": "ok",
  "uptimeSeconds": 812, "version": "0.1.0"
}
```

`registryWarning` is set when a malformed registry was set aside at startup
(registry.md). `lastRegistryWrite` is the file's mtime at load, then the time
of each save.

## Errors

Every error is `{"error":{"code":"…","message":"…"}}`; the message says how to
fix it. Codes are stable (agents branch on them) — add, never rename
(`SubpanelErrorCode`).

| Code | HTTP | When |
|---|---|---|
| `invalid_name` | 400 | name fails validation (message suggests the fix, e.g. the lowercase form) |
| `invalid_target` | 400 | not `http://HOST:PORT`, https, missing port, port 80, path/query present, body lacks `target` |
| `non_loopback_target` | 400 | host isn't `127.0.0.1` / `::1` / `localhost` |
| `malformed_json` | 400 | body isn't JSON |
| `forbidden_origin` | 403 | PUT/DELETE with an `Origin` other than the control origin |
| `mapping_not_found` | 404 | GET of an unknown name; also JSON 404 on an app host |
| `not_found` / `invalid_host` | 404 | unknown API path / host that isn't `*.localhost` |
| `method_not_allowed` | 405 | with an `Allow` header |
| `reserved_name` | 409 | `subpanel` |
| `payload_too_large` | 413 | control body over 64 KiB (connection closed) |
| `internal_error` | 500 | registry save failed (memory left unchanged) |
| `backend_unavailable` | 502 | on an app host: registered, nothing answered |
| `loop_detected` | 508 | on an app host: request passed through Subpanel 8 times |

## Local security model

The API is for agents running as the logged-in user. Documented, deliberate:

- **Any local process can change mappings.** Localhost is not an
  authentication boundary against local malware, and we don't pretend it is.
- **Loopback only**: listeners are 127.0.0.1/::1 via launchd; non-loopback
  peers are dropped at accept; targets must be structurally loopback, so
  Subpanel can't become a localhost→network SSRF relay.
- **Host-gated**: the control plane only answers `Host: subpanel.localhost`,
  so a DNS-rebinding page (`Host: evil.example`) can't reach it, and
  `<name>.localhost/api/...` belongs to the app, not Subpanel.
- **Browsers can't drive it**: mutations are PUT/DELETE, which browsers
  preflight; Subpanel sends no CORS headers, so preflights fail. As defense in
  depth, a PUT/DELETE carrying a foreign `Origin` is refused (403).
- **No process control**: the API can't start, stop or run anything.
