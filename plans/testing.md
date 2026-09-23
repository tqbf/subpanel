# Testing

Testing the proxy matters more than testing SwiftUI details. There are three
layers.

## 1. `make test`: 72 swift-testing tests, about 4 s

| Suite | File | Covers |
|---|---|---|
| Name validation, Target validation, Host routing | `ValidationTests.swift` | every accept/reject case from the spec, and the hints |
| Persistence, Registry | `RegistryTests.swift` | round trip, atomic replace with no temp files left, malformed, unknown-version, and invalid-entry files preserved aside, create/update/unchanged, idempotent delete, snapshot follows mutations, a failed save leaves memory untouched |
| Control API, Markdown rendering | `ControlAPITests.swift` | full CRUD, reserved/invalid names, bad targets and bodies, forbidden Origin, 405/404, status and discovery, content negotiation, instructions contain the convention, per-port URLs |
| Listening sockets | `ListeningSocketsTests.swift` | the libproc scan finds this process's own IPv4/IPv6 listeners (without connecting) and not a closed port; target-to-listener matching incl. wildcards; the index caches scans |
| Proxy (serialized) | `ProxyIntegrationTests.swift` | a real `ProxyServer` on 127.0.0.1+::1 in front of a NIO `BackendFixture`: headers (Host preserved, X-Forwarded-*, Via, hop-by-hop), POST, 32 MiB upload, 8 MiB chunked upload, 48 MiB download (sized and chunked), streaming not buffered (raw-socket timing), SSE, redirects not followed, cookies, HEAD (with and without length, then a second request on the same connection), `Expect: 100-continue`, pipelining in order across a 404, HTTP/1.0, absolute-form, 502/404/508, control plane only on its host, PUT/update/DELETE take effect immediately, `localhost` → IPv6-only backend, WebSocket (server speaks first, text, 200 KB binary, server-initiated close), upgrade to an unknown name → 404 + close |

`ProxyRegressionTests.swift` extends that suite with one test per defect from
the adversarial review:
- A backend status below 100 gets a 502, and the service survives.
- No exchange outlives its response (a DEBUG live counter).
- Idle keep-alive connections are closed.
- A client that half-closes still gets its response.
- A frame sent with a 101 before the backend hangs up is relayed.
- Absolute-form requests work against the control plane.
- A pipelined request after a closing response doesn't swallow that response.
- `Connection: Content-Length` can't smuggle a request.
- CONNECT and TRACE get a 405.
- `Expect: 100-continue` is answered immediately.

The support code is in `Tests/SubpanelTests/Support/`: `BackendFixture` (a
NIO app with the routes above and a WebSocket echo), `ScriptedBackend` (which
writes exact bytes and then optionally hangs up), `ProxyHarness`, and
`RawClient` (a raw TCP exchange with arrival timestamps and optional
half-close).

Test-writing gotchas:
- URLSession content-sniffs `text/plain` and buffers the first 512 bytes, so
  it can't prove streaming. Use `RawClient.timeline`.
- NIO's WebSocket upgrader defaults to a 16 KiB max frame size. The fixture
  raises it.

## 2. `make smoke`: the installed service on port 80

`scripts/smoke.sh` uses curl and python3 only. It checks status, instructions
and discovery, then runs PUT → route (IPv4 and IPv6) → idempotent PUT →
update → persisted on disk → backend down 502 → DELETE → 404, plus reserved
and non-loopback rejection. It leaves nothing behind.
`BASE=http://subpanel.localhost:8080` points it at `make service-dev`.

## 3. Real browser + dev server (manual recipe, run for v1)

In a scratch directory:

```sh
npm i vite puppeteer-core ws
npx vite --host 127.0.0.1 --port $PORT --strictPort &
curl -X PUT http://subpanel.localhost/api/v1/apps/vitehmr -d "{\"target\":\"http://127.0.0.1:$PORT\"}"
```

Drive headless Chrome (`puppeteer-core` with
`executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'`):
load `http://vitehmr.localhost/`, confirm `[vite] connected.` and a 101 on
`ws://vitehmr.localhost/`, edit a CSS file, and confirm the style changes
**without** a reload (a `window` marker survives). The v1 run passed:
`[vite] hot updated: /style.css`, same page.

A second page, served by a Node fixture behind Subpanel, exercised
`fetch` POST (with Host and X-Forwarded-Host seen as `browserfix.localhost`),
`Set-Cookie`/`document.cookie`, `EventSource` (3 events), and a browser
WebSocket echo. All passed in Chrome. Safari wasn't automated. The system
resolver does resolve `*.localhost` (`dscacheutil -q host -a name
foo.localhost`), which Safari relies on.

## UI

`SUBPANEL_SNAPSHOT_DIR` renders every window of Subpanel.app to PNG, and
photographs Subpanel Menu's actual menu (design-system.md). Look at light,
dark, running, down, and empty states after any UI change. The compile gate
isn't sufficient (SWIFTUI-RULES §9).
