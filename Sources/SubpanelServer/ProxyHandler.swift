import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import os
import SubpanelCore

/// Tunables for the proxy. Deliberately few: no read/response timeouts at all,
/// so dev servers, SSE, and WebSockets can take as long as they like.
public struct ProxyConfiguration: Sendable {
    /// The port clients use; shapes generated URLs. 80 in production.
    public var publicPort: Int
    /// How long to wait for a backend to accept a connection.
    public var connectTimeout: TimeAmount = .seconds(5)
    /// How long a client connection may sit *between* requests before we
    /// close it. Never applies mid-request, mid-response, or to upgraded
    /// (WebSocket) connections.
    public var idleTimeout: TimeAmount = .seconds(75)
    /// Largest control-API request body buffered in memory.
    public var controlBodyLimit = 64 * 1024
    /// Largest request body discarded before answering a 404/502 locally;
    /// past this the connection is closed instead.
    public var discardLimit = 1024 * 1024
    /// Log a one-line summary of every request (debug mode).
    public var logRequests = false

    public init(publicPort: Int) {
        self.publicPort = publicPort
    }
}

/// One proxied request/response. Owned by the client connection's
/// `ProxyHandler` (through its state); lives on its event loop. The backend
/// side refers back to it only weakly, so a finished exchange — and its
/// closed backend channel — is freed as soon as the handler moves on.
final class ProxyExchange {
    let head: HTTPRequestHead
    let label: String
    let target: BackendTarget
    let isUpgrade: Bool
    var backend: (any Channel)?
    var backendHandler: BackendHandler?
    /// Request parts received before the backend connection was up.
    var queued: [HTTPClientRequestPart] = []
    var requestComplete = false
    var responseStarted = false
    var responseComplete = false
    var closeClientAfterResponse: Bool
    var upgradeResponse: HTTPResponseHead?

    #if DEBUG
    /// Live instances, for the leak regression test.
    static let live = NIOLockedValueBox(0)
    #endif

    init(head: HTTPRequestHead, label: String, target: BackendTarget) {
        self.head = head
        self.label = label
        self.target = target
        self.isUpgrade = ProxyHeaders.isUpgradeRequest(head)
        self.closeClientAfterResponse = !head.isKeepAlive || head.version.minor == 0
        #if DEBUG
        Self.live.withLockedValue { $0 += 1 }
        #endif
    }

    deinit {
        #if DEBUG
        Self.live.withLockedValue { $0 -= 1 }
        #endif
    }

    /// Drops the backend: stops its callbacks, closes it, forgets it.
    func releaseBackend() {
        backendHandler?.detach()
        backend?.close(promise: nil)
        backendHandler = nil
        backend = nil
    }
}

/// The per-connection handler behind NIO's HTTP/1.1 server pipeline.
///
/// Routes each request by `Host` (plans/proxy.md):
/// - `subpanel.localhost` → buffers the (small) body, answers from `ControlAPI`;
/// - `<name>.localhost` → opens a backend connection and streams both ways
///   with backpressure, never buffering a whole body;
/// - anything else → a local 404.
///
/// A successful `Upgrade` (WebSockets, HMR) swaps both pipelines for a pair
/// of `GlueHandler`s: from then on it's a raw byte tunnel.
///
/// **Re-entrancy rule:** NIO's pipelining handler delivers the next queued
/// request *from inside* the write of a response's `.end`. So every path
/// decides and sets the next state before writing `.end` (PROBLEMS.md).
final class ProxyHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundIn = HTTPServerResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case idle
        /// Buffering a control-plane request.
        case control(HTTPRequestHead, ByteBuffer)
        case awaitingControlResponse
        /// Answering locally (404/502/…) once the request body is consumed.
        case discarding(HTTPRequestHead, LocalResponse, discarded: Int)
        case proxying(ProxyExchange)
        /// A final response is being written; the connection closes after it.
        case closing
        case upgraded
    }

    private let routes: RoutingTable
    private let control: ControlAPI
    private let configuration: ProxyConfiguration
    private let log = Logger(subsystem: SubpanelConstants.logSubsystem, category: "proxy")

    private var state = State.idle
    private var context: ChannelHandlerContext?
    private var pendingRead = false
    /// The client half-closed: finish the current response, then close.
    private var inputClosed = false
    private var idleTimer: Scheduled<Void>?

    init(routes: RoutingTable, control: ControlAPI, configuration: ProxyConfiguration) {
        self.routes = routes
        self.control = control
        self.configuration = configuration
    }

    var clientIsWritable: Bool {
        context?.channel.isWritable ?? false
    }

    // MARK: - Channel events

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        armIdleTimer(context: context)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        idleTimer?.cancel()
        idleTimer = nil
        self.context = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            receivedHead(head, context: context)
        case .body(let buffer):
            receivedBody(buffer, context: context)
        case .end:
            receivedEnd(context: context)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        if case .proxying(let exchange) = state {
            exchange.backendHandler?.flush()
        }
        context.fireChannelReadComplete()
    }

    func channelInactive(context: ChannelHandlerContext) {
        if case .proxying(let exchange) = state {
            exchange.releaseBackend()
        }
        state = .closing
        idleTimer?.cancel()
        context.fireChannelInactive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        // Half-closure is enabled so a client that shuts down its write side
        // after sending a request (`nc`, some HTTP/1.0 tools) still gets the
        // answer. Nothing more can arrive: finish what's in flight, then close.
        if let event = event as? ChannelEvent, case .inputClosed = event {
            inputClosed = true
            if case .idle = state {
                state = .closing
                context.close(promise: nil)
            }
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable, case .proxying(let exchange) = state {
            exchange.backendHandler?.clientBecameWritable()
        }
        context.fireChannelWritabilityChanged()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        log.debug("client connection error: \(String(describing: error), privacy: .public)")
        context.close(promise: nil)
    }

    // Backpressure: stop reading the request body while the backend isn't
    // connected yet or can't accept more.
    func read(context: ChannelHandlerContext) {
        if case .proxying(let exchange) = state, !exchange.requestComplete,
           !(exchange.backendHandler?.isWritable ?? false) {
            pendingRead = true
            return
        }
        context.read()
    }

    private func resumeReading() {
        if pendingRead {
            pendingRead = false
            context?.read()
        }
    }

    // MARK: - Idle keep-alive connections

    /// Closes the connection if it's still between requests after
    /// `idleTimeout`, so abandoned keep-alive connections can't pile up
    /// against the process's file-descriptor limit.
    private func armIdleTimer(context: ChannelHandlerContext) {
        idleTimer?.cancel()
        let bound = NIOLoopBound(self, eventLoop: context.eventLoop)
        let boundContext = context.loopBound
        idleTimer = context.eventLoop.scheduleTask(in: configuration.idleTimeout) {
            guard case .idle = bound.value.state else { return }
            bound.value.state = .closing
            boundContext.value.close(promise: nil)
        }
    }

    // MARK: - Request

    private func receivedHead(_ requestHead: HTTPRequestHead, context: ChannelHandlerContext) {
        switch state {
        case .idle:
            break
        case .closing, .upgraded:
            // A pipelined request after a response that will close the
            // connection. Ignore it; closing here would discard the unflushed
            // response we're in the middle of writing.
            return
        default:
            // NIO's pipelining handler serializes requests, so this can't
            // happen for a well-behaved client.
            context.close(promise: nil)
            return
        }
        idleTimer?.cancel()

        var head = requestHead
        var host = head.headers.first(name: "host")
        if let absolute = ProxyHeaders.splitAbsoluteForm(head.uri) {
            // Absolute-form target: the URI's authority wins (RFC 9112 §3.2.2).
            host = absolute.authority
            head.uri = absolute.uri
        }
        let accept = head.headers.first(name: "accept")
        let port = configuration.publicPort
        let expectsContinue = head.version.minor >= 1
            && head.headers.first(name: "expect")?.lowercased() == "100-continue"

        if configuration.logRequests {
            log.debug("\(head.method.rawValue, privacy: .public) \(host ?? "-", privacy: .public)\(head.uri, privacy: .public)")
        }

        if head.method == .CONNECT || head.method == .TRACE {
            // Subpanel isn't a forward proxy, and TRACE bodies can't be framed
            // to the backend (NIO strips their length headers).
            let error = SubpanelError(.methodNotAllowed, "Subpanel doesn't support \(head.method.rawValue) requests.")
            state = .discarding(head, .error(error), discarded: 0)
        } else {
            switch HostRoute(hostHeader: host) {
            case .control:
                state = .control(head, context.channel.allocator.buffer(capacity: 0))
                if expectsContinue {
                    // We want the body: say so now, or the client waits ~1 s.
                    let continueHead = HTTPResponseHead(version: head.version, status: .continue)
                    context.writeAndFlush(wrapOutboundOut(.head(continueHead)), promise: nil)
                }
            case .app(let label):
                if ProxyHeaders.hopCount(head) >= ProxyHeaders.maxHops {
                    state = .discarding(head, ProxyProblems.loopDetected(label: label, accept: accept, port: port), discarded: 0)
                } else if let target = routes.target(for: label) {
                    let routedHost = host ?? "\(label).\(SubpanelConstants.domain)"
                    startProxying(head: head, host: routedHost, label: label, target: target, context: context)
                } else {
                    state = .discarding(head, ProxyProblems.noMapping(label: label, accept: accept, port: port), discarded: 0)
                }
            case .invalid(let raw):
                state = .discarding(head, ProxyProblems.invalidHost(raw, accept: accept, port: port), discarded: 0)
            }
        }

        // A client waiting for `100 Continue` would otherwise sit out its
        // fallback timer before sending a body we're only going to discard.
        // Answer now and close (whether a body follows is now ambiguous).
        if expectsContinue, case .discarding(let discardedHead, let response, _) = state {
            writeLocal(response, for: discardedHead, context: context, forceClose: true)
        }
    }

    private func receivedBody(_ buffer: ByteBuffer, context: ChannelHandlerContext) {
        switch state {
        case .control(let head, var body):
            guard body.readableBytes + buffer.readableBytes <= configuration.controlBodyLimit else {
                writeLocal(ProxyProblems.payloadTooLarge(limit: configuration.controlBodyLimit), for: head, context: context, forceClose: true)
                return
            }
            state = .closing  // drop the enum's reference so the append doesn't copy
            var buffer = buffer
            body.writeBuffer(&buffer)
            state = .control(head, body)
        case .discarding(let head, let response, let discarded):
            let total = discarded + buffer.readableBytes
            if total > configuration.discardLimit {
                writeLocal(response, for: head, context: context, forceClose: true)
            } else {
                state = .discarding(head, response, discarded: total)
            }
        case .proxying(let exchange):
            guard !exchange.responseComplete else { return }
            sendToBackend(.body(.byteBuffer(buffer)), exchange: exchange)
        case .idle, .awaitingControlResponse, .closing, .upgraded:
            break
        }
    }

    private func receivedEnd(context: ChannelHandlerContext) {
        switch state {
        case .control(let head, let body):
            state = .awaitingControlResponse
            respondToControl(head: head, body: body, context: context)
        case .discarding(let head, let response, _):
            writeLocal(response, for: head, context: context)
        case .proxying(let exchange):
            exchange.requestComplete = true
            if !exchange.responseComplete {
                sendToBackend(.end(nil), exchange: exchange)
                exchange.backendHandler?.flush()
            }
        case .idle, .awaitingControlResponse, .closing, .upgraded:
            break
        }
    }

    // MARK: - Local responses

    private func respondToControl(head: HTTPRequestHead, body: ByteBuffer, context: ChannelHandlerContext) {
        let request = ControlRequest(
            method: head.method.rawValue,
            uri: head.uri,
            headers: Dictionary(head.headers.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { "\($0), \($1)" }),
            body: Data(body.readableBytesView)
        )
        let control = self.control
        let promise = context.eventLoop.makePromise(of: LocalResponse.self)
        promise.completeWithTask { await control.handle(request) }
        promise.futureResult.assumeIsolated().whenSuccess { response in
            guard case .awaitingControlResponse = self.state else { return }
            self.writeLocal(response, for: head, context: context)
        }
    }

    /// Whether the connection can carry another request after answering
    /// `head`. Not after upgrade attempts or CONNECT (NIO's decoder stops
    /// parsing after them), not if the client asked to close or half-closed.
    private func canKeepAlive(after head: HTTPRequestHead) -> Bool {
        head.isKeepAlive && !inputClosed && !ProxyHeaders.isUpgradeRequest(head) && head.method != .CONNECT
    }

    /// Writes a complete response generated by Subpanel.
    private func writeLocal(_ response: LocalResponse, for head: HTTPRequestHead, context: ChannelHandlerContext, forceClose: Bool = false) {
        let keepAlive = canKeepAlive(after: head) && !forceClose
        var headers = HTTPHeaders(response.headers.map { ($0.name, $0.value) })
        headers.replaceOrAdd(name: "Content-Length", value: String(response.body.count))
        headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        if !keepAlive {
            headers.replaceOrAdd(name: "Connection", value: "close")
        }
        let responseHead = HTTPResponseHead(
            version: head.version,
            status: HTTPResponseStatus(statusCode: response.status),
            headers: headers
        )
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        if head.method != .HEAD, !response.body.isEmpty {
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: response.body)))), promise: nil)
        }
        endResponse(keepAlive: keepAlive, context: context)
    }

    /// Writes `.end` — after setting the next state (see the re-entrancy
    /// rule above) — then either waits for the next request or closes.
    private func endResponse(keepAlive: Bool, context: ChannelHandlerContext) {
        if keepAlive {
            state = .idle
            armIdleTimer(context: context)
        } else {
            state = .closing
        }
        let written = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if keepAlive {
            resumeReading()
        } else {
            written.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        }
    }

    // MARK: - Proxying

    private func startProxying(head: HTTPRequestHead, host: String, label: String, target: BackendTarget, context: ChannelHandlerContext) {
        let exchange = ProxyExchange(head: head, label: label, target: target)
        exchange.queued.append(.head(ProxyHeaders.backendHead(
            for: head,
            uri: head.uri,
            host: host,
            clientAddress: context.channel.remoteAddress?.ipAddress
        )))
        state = .proxying(exchange)

        let boundSelf = NIOLoopBound(self, eventLoop: context.eventLoop)
        let boundExchange = NIOLoopBound(exchange, eventLoop: context.eventLoop)
        // Same event loop as the client, so the two channels can call each
        // other synchronously.
        let connect = ClientBootstrap(group: context.eventLoop)
            .connectTimeout(configuration.connectTimeout)
            .channelOption(.socketOption(.tcp_nodelay), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandlers([
                        HTTPRequestEncoder(),
                        UpgradeGate(),
                        ByteToMessageHandler(HTTPResponseDecoder(
                            leftOverBytesStrategy: .forwardBytes,
                            informationalResponseStrategy: .forward
                        )),
                        BackendHandler(proxy: boundSelf.value, exchange: boundExchange.value),
                    ])
                }
            }
            // "localhost" resolves to ::1 and 127.0.0.1; NIO tries both
            // (Happy Eyeballs), which is what the instructions promise.
            .connect(host: target.host, port: target.port)

        connect.assumeIsolated().whenComplete { result in
            switch result {
            case .success(let channel):
                self.backendConnected(channel, exchange: exchange)
            case .failure(let error):
                self.backendFailed(error, exchange: exchange)
            }
        }
    }

    private func isCurrent(_ exchange: ProxyExchange) -> Bool {
        if case .proxying(let current) = state, current === exchange { return true }
        return false
    }

    private func sendToBackend(_ part: HTTPClientRequestPart, exchange: ProxyExchange) {
        if let handler = exchange.backendHandler {
            handler.send(part)
        } else {
            exchange.queued.append(part)
        }
    }

    private func backendConnected(_ channel: any Channel, exchange: ProxyExchange) {
        guard isCurrent(exchange),
              let handler = try? channel.pipeline.syncOperations.handler(type: BackendHandler.self)
        else {
            channel.close(promise: nil)
            return
        }
        exchange.backend = channel
        exchange.backendHandler = handler
        for part in exchange.queued {
            handler.send(part)
        }
        exchange.queued = []
        handler.flush()
        if channel.isWritable {
            resumeReading()
        }
    }

    private func backendFailed(_ error: any Error, exchange: ProxyExchange) {
        guard isCurrent(exchange), let context else { return }
        log.info("backend \(exchange.target.authority, privacy: .public) for \(exchange.label, privacy: .public) unavailable: \(String(describing: error), privacy: .public)")
        let response = unavailable(exchange)
        if exchange.requestComplete {
            writeLocal(response, for: exchange.head, context: context)
        } else {
            state = .discarding(exchange.head, response, discarded: 0)
            resumeReading()
        }
    }

    private func unavailable(_ exchange: ProxyExchange) -> LocalResponse {
        ProxyProblems.backendUnavailable(
            label: exchange.label,
            target: exchange.target,
            accept: exchange.head.headers.first(name: "accept"),
            port: configuration.publicPort
        )
    }

    // MARK: - Backend callbacks (same event loop)

    func backendReceived(_ part: HTTPClientResponsePart, exchange: ProxyExchange) {
        guard isCurrent(exchange), let context else { return }
        switch part {
        case .head(let response) where response.status == .switchingProtocols:
            if exchange.isUpgrade {
                exchange.upgradeResponse = response  // switch over at .end
            } else {
                log.error("backend \(exchange.target.authority, privacy: .public) sent 101 without an upgrade request")
                exchange.backend?.close(promise: nil)  // → backendClosed → 502
            }
        case .head(let response) where response.status.code < 100:
            // Not a valid status. NIO's decoder accepts 000–099, but its
            // server-side handlers don't treat them as informational; relaying
            // one crashes the service (precondition). It's a bad backend: 502.
            log.error("backend \(exchange.target.authority, privacy: .public) sent invalid status \(response.status.code)")
            exchange.backend?.close(promise: nil)
        case .head(let response) where response.status.code < 200:
            // 100 Continue and friends: pass straight through (not to HTTP/1.0).
            guard exchange.head.version.minor > 0 else { return }
            let head = ProxyHeaders.clientHead(for: response, requestVersion: exchange.head.version, closeAfter: false, upgrade: false)
            context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
        case .head(let response):
            exchange.responseStarted = true
            // A declined upgrade (or CONNECT) leaves NIO's request decoder
            // stopped, and a half-closed client can't send more: close after.
            if !canKeepAlive(after: exchange.head) {
                exchange.closeClientAfterResponse = true
            }
            let head = ProxyHeaders.clientHead(
                for: response,
                requestVersion: exchange.head.version,
                closeAfter: exchange.closeClientAfterResponse,
                upgrade: false
            )
            context.write(wrapOutboundOut(.head(head)), promise: nil)
        case .body(let buffer):
            guard exchange.responseStarted else { return }
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        case .end:
            if let upgrade = exchange.upgradeResponse {
                completeUpgrade(exchange, response: upgrade, context: context)
            } else if exchange.responseStarted {
                finishResponse(exchange, context: context)
            }
        }
    }

    func backendReadComplete(exchange: ProxyExchange) {
        guard isCurrent(exchange) else { return }
        context?.flush()
    }

    func backendBecameWritable(exchange: ProxyExchange) {
        guard isCurrent(exchange) else { return }
        resumeReading()
    }

    func backendClosed(exchange: ProxyExchange, channel: any Channel) {
        guard isCurrent(exchange), exchange.backend === channel, !exchange.responseComplete, let context else { return }
        exchange.releaseBackend()
        if exchange.responseStarted || exchange.upgradeResponse != nil {
            // Truncated mid-response; the client must see the connection end.
            state = .closing
            context.close(promise: nil)
            return
        }
        // Accepted the connection but closed (or was closed) without a usable
        // response.
        log.info("backend \(exchange.target.authority, privacy: .public) for \(exchange.label, privacy: .public) closed without a response")
        writeLocal(unavailable(exchange), for: exchange.head, context: context, forceClose: !exchange.requestComplete)
    }

    private func finishResponse(_ exchange: ProxyExchange, context: ChannelHandlerContext) {
        exchange.responseComplete = true
        exchange.releaseBackend()
        // If the backend answered before the request body finished (e.g. an
        // early 413), close rather than drain the rest of the upload.
        let keepAlive = !exchange.closeClientAfterResponse && exchange.requestComplete && !inputClosed
        endResponse(keepAlive: keepAlive, context: context)
    }

    // MARK: - Upgrade

    /// The backend accepted the upgrade: forward the 101, then turn both
    /// connections into a raw byte tunnel.
    ///
    /// Runs synchronously within the backend read that delivered the 101, so
    /// NIO can't read anything from the client between the 101 being written
    /// and the HTTP handlers being removed. (NIO's request decoder drops
    /// bytes left over after an upgrade request; a conforming client sends
    /// none before it sees the 101.)
    ///
    /// On the backend side, bytes that arrived with the 101 sit in the
    /// response decoder, which forwards them (`.forwardBytes`) only when its
    /// deferred removal completes — and only if it hasn't seen EOF. The
    /// `UpgradeGate` in front of it holds any later reads and the EOF until
    /// then, so a backend that sends a frame and hangs up at once is relayed
    /// intact.
    private func completeUpgrade(_ exchange: ProxyExchange, response: HTTPResponseHead, context: ChannelHandlerContext) {
        guard let backend = exchange.backend,
              let backendHandler = exchange.backendHandler,
              let gate = try? backend.pipeline.syncOperations.handler(type: UpgradeGate.self)
        else {
            context.close(promise: nil)
            return
        }
        let head = ProxyHeaders.clientHead(for: response, requestVersion: exchange.head.version, closeAfter: false, upgrade: true)
        state = .upgraded
        idleTimer?.cancel()
        gate.hold()
        exchange.backendHandler = nil
        exchange.backend = nil
        backendHandler.detach()
        context.write(wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)

        let clientChannel = context.channel
        let (clientGlue, backendGlue) = GlueHandler.matchedPair()
        do {
            let client = context.pipeline.syncOperations
            try client.addHandler(clientGlue)
            try client.removeHandler(client.handler(type: ByteToMessageHandler<HTTPRequestDecoder>.self), promise: nil)
            try client.removeHandler(client.handler(type: HTTPResponseEncoder.self), promise: nil)
            try client.removeHandler(client.handler(type: HTTPServerPipelineHandler.self), promise: nil)
            try? client.removeHandler(client.handler(type: NIOHTTPResponseHeadersValidator.self), promise: nil)
            try? client.removeHandler(client.handler(type: HTTPServerProtocolErrorHandler.self), promise: nil)
            client.removeHandler(context: context, promise: nil)

            let server = backend.pipeline.syncOperations
            try server.addHandler(backendGlue)
            server.removeHandler(backendHandler, promise: nil)
            try server.removeHandler(server.handler(type: HTTPRequestEncoder.self), promise: nil)
            let decoderRemoved = backend.eventLoop.makePromise(of: Void.self)
            try server.removeHandler(server.handler(type: ByteToMessageHandler<HTTPResponseDecoder>.self), promise: decoderRemoved)
            decoderRemoved.futureResult.assumeIsolated().whenComplete { _ in
                // The decoder has forwarded its leftovers into the glue;
                // nothing flushes those, so flush — then let through whatever
                // the gate held (later reads, EOF), and step out of the way.
                clientChannel.flush()
                gate.release()
            }
        } catch {
            log.error("upgrade for \(exchange.label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            backend.close(promise: nil)
            clientChannel.close(promise: nil)
            return
        }
        // Handlers we removed may have been sitting on a withheld read.
        clientChannel.read()
        backend.read()
    }
}
