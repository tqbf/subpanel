# Problems — things that bit us

One entry per hard-won lesson, specific to this app (`SWIFTUI-RULES.md` §10.2).
Read these before touching the proxy state machine, the install flow, or the
snapshot tool.

---

## NIO's pipelining handler re-enters you when you write `.end`

With `configureHTTPServerPipeline(withPipeliningAssistance: true)`, writing a
response's `.end` makes `HTTPServerPipelineHandler` deliver the **next queued
request synchronously, from inside that write call**. We set
`state = .idle` *after* the write, so the next request's `.head` arrived while
we were still "proxying". It hit a guard and the connection closed.
Symptom: pipelined `HEAD` + `GET` returned nothing. **Rule: decide and set the
next state before writing `.end`.** (`writeLocal`, `finishResponse`,
`completeUpgrade`.)

## Bytes forwarded by a removed decoder aren't flushed

Removing `ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy:
.forwardBytes))` after a 101 forwards the bytes the backend sent in the same
packet (for example a WebSocket server's first frame). The removal is
deferred a tick, and the forward fires `channelRead` with **no**
`channelReadComplete`, so the glue writes but never flushes. The frame sat
there until the next backend read, which for a server that speaks first may
never come. **Fix: flush the client when the decoder's removal promise
completes.**

## `swift-http-server` can't be used here (yet)

Its releases need swift-tools-version 6.4 (Xcode ships 6.3.3), it can't adopt
a launchd-bound socket, and it has no HTTP upgrade hook. See
`plans/proxy.md`. Don't re-evaluate it until all three change.

## Two copies of the app confuse Background Task Management

We registered the agent from `build/Subpanel.app` and then from
`/Applications/Subpanel.app`, both with the same bundle ID. BTM kept
resolving the agent through the dev copy, whose code hash changes on every
rebuild ("needs LWCR update"). launchd ended up with a job it couldn't
resolve: `Could not find and/or execute program … No such process`, retried
every 10 s, while connections to port 80 queued and hung. **Fix:** unregister
from *both* copies (`--uninstall-service` on each), then register from one.
`make install` does this automatically now. Also, don't
`launchctl kickstart -k` right after `register()`: registration already
starts the job.

## A backend status below 100 crashed the whole service

NIO's response decoder accepts `000`–`099`. We forwarded them as "1xx"
(`code < 200`), but NIO's server-side error handler doesn't count them as
informational. It recorded a response as started, and the next head we
wrote tripped a `precondition`, killing every app's connections. Now:
`code < 100` means a bad backend, which gets a 502. **Use
`(100..<200).contains`, never `< 200`, for "informational".**

## BackendHandler ↔ ProxyExchange was a reference cycle

Every proxied request leaked its exchange and its closed backend channel,
about 4.75 KB each. `leaks` showed `ROOT CYCLE: BackendHandler ↔
ProxyExchange → SocketChannel`. The backend handler's references to the
exchange and the proxy handler are now `weak`, and a DEBUG-only live counter
backs a regression test.

## Deferred handler removal and EOF

After a 101, the response decoder's removal is deferred a tick. If the
backend's EOF arrives in the same read loop, the decoder runs its final pass
with `seenEOF: true` and silently drops its leftovers, so a frame sent with
the 101 was lost. `UpgradeGate`, placed in front of the decoder, holds later
reads and the EOF until the removal completes.

## Headers named in `Connection` can include framing headers

`Connection: close, Content-Length` made us strip `Content-Length` as
hop-by-hop. NIO then sent a GET body unframed: a smuggled second request.
`Content-Length` and `Host` are now never removed that way. TRACE (whose
length headers NIO strips) and CONNECT (after which NIO stops parsing) are
refused with a 405.

## An old binary given a new flag launched its GUI mid-install

`make install` ran the *installed* (older) Subpanel with `--uninstall-menu`,
a flag it didn't know. It launched its GUI instead and hung the install.
Worse, its first-run Welcome window saw the service had just been
unregistered and **re-registered it from the old bundle**, which was then
deleted. Background Task Management invalidated the item, and launchd failed
with `Unable to get updated LWCR … Invalid argument`, then `copy_bundle_path …
Invalid or missing Program`. Port 80 hung. Fixes: unknown `--` flags now
exit 64, and `make install` drives only the freshly built binary. (Registering
the menu login item next to the agent is fine. That was tested and ruled out
as the cause.)

## A SwiftUI menu item's subtitle has a specific shape

In a `.menu`-style `MenuBarExtra`, `Button { Label(title, systemImage:);
Text(subtitle) }` renders a native item with an icon and a subtitle. Put the
second `Text` *inside* the Label (`Label { Text; Text } icon: {…}`) and the
subtitle is silently dropped. With no Label, you get a subtitle but no icon.
Verified with `MenuSnapshot`.

## `sfltool dumpbtm` hangs in an agent shell

It waits for an authorization prompt that never appears. Use
`launchctl print gui/$(id -u)/org.sockpuppet.subpanel.service` and
`log show --predicate 'process == "launchd" AND eventMessage CONTAINS "subpanel"'`
instead.

## Grouped `Form`s snapshot blank with `cacheDisplay` / `CALayer.render`

SwiftUI draws grouped forms inside a hosting scroll view on the GPU, so both
CPU capture paths produce an empty window even though the content is there
(the view hierarchy dump shows it). Capture your own windows through the
window server instead. `CGWindowListCreateImage` is "unavailable" in Swift
but still exists: look it up with `dlsym` (`DevSnapshot.swift`). Also, a
grouped Form has no intrinsic height: `.fixedSize(vertical:)` on it makes a
huge, empty window. Give each settings tab an explicit height.

## URLSession can't prove streaming

It content-sniffs `text/plain` and buffers the first 512 bytes, so a streamed
response looks buffered. Time arrivals on a raw socket (`RawClient.timeline`).

## NIO's WebSocket upgrader drops frames over 16 KiB by default

`NIOWebSocketServerUpgrader(maxFrameSize:)` defaults to 1<<14. A 200 KB test
message killed the fixture's connection, which surfaced as a confusing
"Socket is not connected" in URLSession. It wasn't the proxy.

## A test fixture that recursed through synchronous write futures (SIGBUS)

`writeAndFlush(...).whenSuccess { writeNext() }` can complete synchronously,
so a 48 MiB download recursed about 800 levels deep and blew the stack.
Break the recursion with `eventLoop.execute`.

## Renaming has to keep four names in agreement (template heritage)

The SwiftPM target, `APP_NAME` in `build.sh`, `CFBundleExecutable`, and the
entitlements path must match. The service adds a fifth pair: the product
name `subpanel-service` must match the plist's `BundleProgram`.
