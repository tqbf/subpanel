import Foundation
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
/// `ProxyHandler`; lives on its event loop.
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

    init(head: HTTPRequestHead, label: String, target: BackendTarget) {
        self.head = head
        self.label = label
        self.target = target
        self.isUpgrade = ProxyHeaders.isUpgradeRequest(head)
        self.closeClientAfterResponse = !head.isKeepAlive || head.version.minor == 0
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
    }

    func handlerRemoved(context: ChannelHandlerContext) {
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
            exchange.backendHandler?.detach()
            exchange.backend?.close(promise: nil)
        }
        state = .closing
        context.fireChannelInactive()
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

    // MARK: - Request

    private func receivedHead(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
        guard case .idle = state else {
            // NIO's pipelining handler serializes requests, so this can't happen
            // for a well-behaved client.
            context.close(promise: nil)
            return
        }
        var uri = head.uri
        var host = head.headers.first(name: "host")
        if let absolute = ProxyHeaders.splitAbsoluteForm(head.uri) {
            host = absolute.authority
            uri = absolute.uri
        }
        let accept = head.headers.first(name: "accept")
        let port = configuration.publicPort

        if configuration.logRequests {
            log.debug("\(head.method.rawValue, privacy: .public) \(host ?? "-", privacy: .public)\(uri, privacy: .public)")
        }

        switch HostRoute(hostHeader: host) {
        case .control:
            state = .control(head, context.channel.allocator.buffer(capacity: 0))
        case .app(let label):
            if ProxyHeaders.hopCount(head) >= ProxyHeaders.maxHops {
                state = .discarding(head, ProxyProblems.loopDetected(label: label, accept: accept, port: port), discarded: 0)
            } else if let target = routes.target(for: label) {
                startProxying(head: head, uri: uri, host: host ?? "\(label).\(SubpanelConstants.domain)", label: label, target: target, context: context)
            } else {
                state = .discarding(head, ProxyProblems.noMapping(label: label, accept: accept, port: port), discarded: 0)
            }
        case .invalid(let raw):
            state = .discarding(head, ProxyProblems.invalidHost(raw, accept: accept, port: port), discarded: 0)
        }
    }

    private func receivedBody(_ buffer: ByteBuffer, context: ChannelHandlerContext) {
        switch state {
        case .control(let head, var body):
            guard body.readableBytes + buffer.readableBytes <= configuration.controlBodyLimit else {
                writeLocal(ProxyProblems.payloadTooLarge(limit: configuration.controlBodyLimit), for: head, context: context, forceClose: true)
                return
            }
            state = .idle  // drop the enum's reference so the append doesn't copy
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

    // MARK: - Control plane

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

    /// Writes a complete response generated by Subpanel. Closes the
    /// connection afterwards when asked to, when the client asked to, or when
    /// the request was an upgrade attempt (NIO's decoder stops parsing after
    /// one, so the connection can't carry another request).
    private func writeLocal(_ response: LocalResponse, for head: HTTPRequestHead, context: ChannelHandlerContext, forceClose: Bool = false) {
        let keepAlive = head.isKeepAlive && !forceClose && !ProxyHeaders.isUpgradeRequest(head)
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
        // Set the next state *before* writing `.end`: NIO's pipelining handler
        // delivers the next queued request re-entrantly from inside that write.
        state = keepAlive ? .idle : .closing
        let written = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if !keepAlive {
            written.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        }
    }

    // MARK: - Proxying

    private func startProxying(head: HTTPRequestHead, uri: String, host: String, label: String, target: BackendTarget, context: ChannelHandlerContext) {
        let exchange = ProxyExchange(head: head, label: label, target: target)
        exchange.queued.append(.head(ProxyHeaders.backendHead(
            for: head,
            uri: uri,
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
        let response = ProxyProblems.backendUnavailable(
            label: exchange.label,
            target: exchange.target,
            accept: exchange.head.headers.first(name: "accept"),
            port: configuration.publicPort
        )
        if exchange.requestComplete {
            writeLocal(response, for: exchange.head, context: context)
        } else {
            state = .discarding(exchange.head, response, discarded: 0)
            resumeReading()
        }
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
                exchange.backend?.close(promise: nil)
            }
        case .head(let response) where response.status.code < 200:
            // 100 Continue and friends: pass straight through (not to HTTP/1.0).
            guard exchange.head.version.minor > 0 else { return }
            let head = ProxyHeaders.clientHead(for: response, requestVersion: exchange.head.version, closeAfter: false, upgrade: false)
            context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
        case .head(let response):
            exchange.responseStarted = true
            // A declined upgrade leaves NIO's request decoder stopped: close after.
            if exchange.isUpgrade {
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
        exchange.backendHandler?.detach()
        if exchange.responseStarted || exchange.upgradeResponse != nil {
            // Truncated mid-response; the client must see the connection end.
            state = .closing
            context.close(promise: nil)
            return
        }
        // Accepted the connection but closed without answering.
        log.info("backend \(exchange.target.authority, privacy: .public) for \(exchange.label, privacy: .public) closed without a response")
        let response = ProxyProblems.backendUnavailable(
            label: exchange.label,
            target: exchange.target,
            accept: exchange.head.headers.first(name: "accept"),
            port: configuration.publicPort
        )
        writeLocal(response, for: exchange.head, context: context, forceClose: !exchange.requestComplete)
    }

    private func finishResponse(_ exchange: ProxyExchange, context: ChannelHandlerContext) {
        exchange.responseComplete = true
        exchange.backendHandler?.detach()
        exchange.backend?.close(promise: nil)

        // If the backend answered before the request body finished (e.g. an
        // early 413), close rather than drain the rest of the upload.
        let closeClient = exchange.closeClientAfterResponse || !exchange.requestComplete
        // Before writing `.end`: the next pipelined request arrives re-entrantly.
        state = closeClient ? .closing : .idle
        let written = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if closeClient {
            written.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        } else {
            resumeReading()
        }
    }

    // MARK: - Upgrade

    /// The backend accepted the upgrade: forward the 101, then turn both
    /// connections into a raw byte tunnel.
    ///
    /// Runs synchronously within the backend read that delivered the 101, so
    /// NIO can't read anything from the client between the 101 being written
    /// and the HTTP handlers being removed. (NIO's request decoder drops
    /// bytes left over after an upgrade request; a conforming client sends
    /// none before it sees the 101.) Bytes the backend sent right after its
    /// 101 are forwarded by its decoder (`.forwardBytes`) into the glue.
    private func completeUpgrade(_ exchange: ProxyExchange, response: HTTPResponseHead, context: ChannelHandlerContext) {
        guard let backend = exchange.backend, let backendHandler = exchange.backendHandler else {
            context.close(promise: nil)
            return
        }
        let head = ProxyHeaders.clientHead(for: response, requestVersion: exchange.head.version, closeAfter: false, upgrade: true)
        state = .upgraded
        exchange.backendHandler?.detach()
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
            // The decoder's removal is deferred a tick; when it completes it has
            // forwarded any bytes the backend sent after its 101 into the glue,
            // but nothing flushes them — so flush here.
            let decoderRemoved = backend.eventLoop.makePromise(of: Void.self)
            try server.removeHandler(server.handler(type: ByteToMessageHandler<HTTPResponseDecoder>.self), promise: decoderRemoved)
            decoderRemoved.futureResult.assumeIsolated().whenComplete { _ in clientChannel.flush() }
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
