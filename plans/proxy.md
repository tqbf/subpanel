# The reverse proxy

Source: `Sources/SubpanelServer/`. Tests:
`Tests/SubpanelTests/ProxyIntegrationTests.swift` (real sockets, a NIO backend
fixture, URLSession + raw-socket clients).

## Why SwiftNIO directly, not swift-http-server

The plan asked for `swift-http-server`'s `NIOHTTPServer`. It was evaluated
(Sep 2026, tags 0.1.0/0.2.0 and main) and rejected for three independent
reasons:

1. **Toolchain.** Every release requires swift-tools-version 6.4; this
   machine's Xcode ships Swift 6.3.3. The last 6.2-compatible revision is a
   pre-0.1 snapshot with an unstable API.
2. **launchd sockets.** Its listener only binds host+port (`BindTarget`); it
   can't adopt an already-bound descriptor. Owning port 80 without root
   depends on exactly that (service-lifecycle.md).
3. **Upgrades.** Its HTTP/1.1 path has no upgrade/raw-tunnel hook, and
   WebSockets are a v1 requirement.

It's also built on SwiftNIO, so we use the same primitives underneath it,
and no framework (Vapor, Hummingbird) is involved. Dependency: `swift-nio`
only, pinned `exact: "2.103.0"`. Revisit swift-http-server when it ships a
6.3-compatible release with bound-socket and upgrade support.

## Pipeline

Per accepted connection (`ProxyServer.bootstrap`):

```
[HTTPResponseEncoder, ByteToMessageHandler(HTTPRequestDecoder),
 HTTPServerPipelineHandler, NIOHTTPResponseHeadersValidator,
 HTTPServerProtocolErrorHandler]  ← configureHTTPServerPipeline
 + ProxyHandler
```

`configureHTTPServerPipeline` is used (not hand-assembled handlers) because it
wires the request decoder to the response encoder internally, which is how
NIO knows a response answers a HEAD and must not carry a body or chunk
terminator.

Per backend connection (`ProxyHandler.startProxying`), on the **same event
loop** as the client:

```
[HTTPRequestEncoder, UpgradeGate, ByteToMessageHandler(HTTPResponseDecoder(
    leftOverBytesStrategy: .forwardBytes, informationalResponseStrategy: .forward)),
 BackendHandler]
```

## Routing (`HostRoute`)

`Host` is lowercased, port and trailing dot stripped. `subpanel.localhost` →
control plane; `<label>.localhost` (single label) → registry lookup;
anything else (bare `localhost`, IPs, other domains, `a.b.localhost`) → 404
`invalid_host`. Absolute-form request targets (`GET http://x.localhost/…`)
route by the URI's authority. No wildcards.

## `ProxyHandler` state machine

```
idle ─head(subpanel)──▶ control(head, body≤64KiB) ─end─▶ awaitingControlResponse ─▶ idle/closing
     ─head(app, known)─▶ proxying(exchange) ─backend .end─▶ idle/closing
                                         └─backend 101──▶ upgraded (handler removed)
     ─head(other)──────▶ discarding(head, 404/508/502, ≤1MiB) ─end─▶ idle/closing
```

Rules that bit us (see PROBLEMS.md):

- **Set the next state before writing `.end`.** NIO's pipelining handler
  delivers the next queued request re-entrantly from inside that write.
  A request that arrives while `.closing` is ignored, not answered with a
  close; closing would discard the response being flushed.
- Idle keep-alive connections (state `.idle`) close after 75 s. Nothing
  closes mid-request, mid-response, or once upgraded.
- Half-closure is enabled. A client that shuts down its write side after
  sending still gets the response, and the connection closes after it.
- CONNECT and TRACE are refused with a 405. `Expect: 100-continue` gets an
  immediate `100 Continue` from the control plane, and an immediate
  final response (plus close) when Subpanel is answering locally anyway.
- Local responses (404/502/API) are written at the request's `.end`, after
  discarding its body (up to 1 MiB, else close). Upgrade requests always
  close after a local response: NIO's request decoder stops parsing after an
  upgrade request, so the connection can't carry another.

## Streaming and backpressure

Nothing is buffered whole. Parts arriving before the backend connects are
queued (bounded by one read) while client reads are withheld.
`ProxyHandler.read` withholds client reads while the backend isn't connected
or isn't writable; `BackendHandler.read` withholds backend reads while the
client isn't writable; `channelWritabilityChanged` on either side re-issues
the withheld read. Flushes happen at `channelReadComplete`.

**One backend connection per request** (sent `Connection: close`). Loopback
connects are cheap and it removes a whole class of pooling bugs. If this
becomes a bottleneck, reuse per client connection, not a global pool.

## Headers (`ProxyHeaders`)

To the backend:
- Method, target (path + query), and ordinary headers pass through.
- **`Host` is preserved** (`wiki.localhost`, including a dev port). Dev
  servers build origin-aware URLs and HMR endpoints from it. Chosen, tested,
  and documented to agents.
- Hop-by-hop headers are removed (`Connection`, `Keep-Alive`,
  `Proxy-Authenticate`, `Proxy-Authorization`, `TE`, `Trailer`,
  `Transfer-Encoding`, `Upgrade`, `Proxy-Connection`, plus any header named
  in `Connection`), **except** `Content-Length` and `Host`. Removing those
  because `Connection` names them would unframe the body and smuggle a
  request. For upgrades, `Connection: Upgrade` and `Upgrade` are
  re-added. Chunked request bodies keep `Transfer-Encoding: chunked`.
- `X-Forwarded-For`, `X-Forwarded-Host`, `X-Forwarded-Proto: http` and
  `Forwarded: for=…;host=…;proto=http` are **set** (not appended). Subpanel
  is the edge, since nothing sits in front of port 80.
- `Via: 1.1 subpanel` is appended. With 8 Subpanel hops the request gets a 508
  instead. More than one hop is legitimate: app A can call app B through
  Subpanel.

Back to the client, the response is stripped of hop-by-hop headers and
re-framed by NIO's encoder. Content-Length is kept, unknown lengths become
chunked, HTTP/1.0 clients get close-delimited responses, and HEAD is
body-free. 1xx responses (for example `100 Continue`) are forwarded to
HTTP/1.1 clients.

## Upgrades (WebSockets, HMR)

When the backend answers `101` to an upgrade request, `completeUpgrade` runs
synchronously within that backend read:

1. It writes the 101 (with `Connection: Upgrade` and `Upgrade`) and flushes.
2. It adds a `GlueHandler` to each pipeline, then removes the HTTP codecs,
   the pipelining helpers and `ProxyHandler` on the client side, and the
   codecs and `BackendHandler` on the backend side.
3. After the backend decoder's removal completes, it flushes the client.
   Removal is deferred a tick. The decoder then forwards any bytes the backend
   sent right after its 101 (`.forwardBytes`), but nothing flushes them, so
   step 3 does. It forwards them only if it hasn't seen EOF. An
   `UpgradeGate`, placed in front of the decoder, holds later reads and the
   EOF until then, and then releases them in order.
4. It issues a `read()` on both channels. A removed handler may have been
   holding a read back.

The glue tunnel has symmetric backpressure. It passes half-close through,
and when either side closes it closes the partner after pending writes flush.
It has no idle timeouts. If the backend declines the upgrade
(anything other than 101), its response is relayed and the client connection
is closed.

## Failures

| Situation | Response |
|---|---|
| No mapping for the label | 404 `mapping_not_found`, with the command to register it |
| Connection refused or timed out (5 s) | 502 `backend_unavailable`, naming the target |
| Backend accepted, then closed with no response | 502 |
| Backend closed partway through the response | Client connection is closed (truncated) |
| Malformed backend response, or a status below 100 | Backend is closed. Then 502 or truncation, per the rows above. (Relaying a status below 100 used to crash the service.) |

Every Subpanel-generated page is negotiated: HTML for browsers, JSON for
`Accept: application/json`, plain text for everything else (`ProxyProblems`).
Nothing includes a stack trace.

## Limits and timeouts

- Backend connect timeout: 5 s. Idle keep-alive connections time out after
  75 s *between* requests.
- **No read or response timeouts.** Compilers, SSE, WebSockets, and long
  polls can take as long as they need.
- The service raises its descriptor soft limit (launchd agents start at 256)
  to 65,536, or 10,240 if that fails. Each proxied request holds two
  descriptors.
- Control request bodies: 64 KiB. Discarded bodies before a local response:
  1 MiB. There is no limit on proxied bodies.
- Only loopback peers are accepted.
