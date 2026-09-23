import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// A small NIO web app that the proxy tests put behind Subpanel. Routes:
///
/// - `/echo`            JSON of what it received (method, uri, headers, body)
/// - `/upload`          `{"bytes": N}` — counts the body without keeping it
/// - `/download?bytes=N[&chunked=1]` N bytes of "x", with or without a length
/// - `/stream`          three chunks, 250 ms apart
/// - `/sse`             three server-sent events, 150 ms apart
/// - `/redirect`        302 to `/echo?from=redirect`
/// - `/cookie/set`, `/cookie/get`
/// - `/continue`        sends `100 Continue` when asked, then echoes
/// - `/ws`              WebSocket: says "hello" first, echoes text and binary,
///                      closes on "close-me"
///
/// Every response carries `X-Fixture: <id>` so tests can tell which backend
/// answered.
final class BackendFixture: Sendable {
    let channel: any Channel
    let id: String

    var port: Int { channel.localAddress!.port! }

    private init(channel: any Channel, id: String) {
        self.channel = channel
        self.id = id
    }

    static func start(host: String = "127.0.0.1", port: Int = 0, id: String = "fixture") async throws -> BackendFixture {
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: 1 << 20,  // NIO's default is 16 KiB
            shouldUpgrade: { channel, head in
                channel.eventLoop.makeSucceededFuture(head.uri == "/ws" ? HTTPHeaders() : nil)
            },
            upgradePipelineHandler: { channel, _ in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(WebSocketEchoHandler())
                }
            }
        )
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let pipeline = channel.pipeline.syncOperations
                    try pipeline.configureHTTPServerPipeline(
                        withServerUpgrade: (upgraders: [upgrader], completionHandler: { context in
                            context.pipeline.syncOperations.removeHandler(name: "fixture", promise: nil)
                        })
                    )
                    try pipeline.addHandler(FixtureHandler(id: id), name: "fixture")
                }
            }
            .bind(host: host, port: port)
            .get()
        return BackendFixture(channel: channel, id: id)
    }

    func stop() async {
        try? await channel.close()
    }
}

private final class FixtureHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    let id: String
    private var head: HTTPRequestHead?
    private var bodyBytes = 0
    private var body = ByteBuffer()

    init(id: String) {
        self.id = id
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            self.head = head
            bodyBytes = 0
            body.clear()
            if head.uri.hasPrefix("/continue"), head.headers.first(name: "expect")?.lowercased() == "100-continue" {
                context.writeAndFlush(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .continue))), promise: nil)
            }
        case .body(var buffer):
            bodyBytes += buffer.readableBytes
            if body.readableBytes < 1 << 16 {
                body.writeBuffer(&buffer)
            }
        case .end:
            guard let head else { return }
            respond(to: head, context: context)
        }
    }

    private func respond(to head: HTTPRequestHead, context: ChannelHandlerContext) {
        let components = URLComponents(string: "http://fixture\(head.uri)")
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        switch components?.path ?? "/" {
        case "/echo", "/continue":
            json(context, head: head, [
                "method": head.method.rawValue,
                "uri": head.uri,
                "headers": head.headers.map { [$0.name.lowercased(), $0.value] },
                "bodyLength": bodyBytes,
                "body": String(buffer: body),
            ], extra: [("X-Echo", "yes")])
        case "/upload":
            json(context, head: head, ["bytes": bodyBytes])
        case "/download":
            let total = Int(query["bytes"] ?? "0") ?? 0
            var headers = HTTPHeaders([("X-Fixture", id), ("Content-Type", "application/octet-stream")])
            if query["chunked"] == nil {
                headers.add(name: "Content-Length", value: String(total))
            }
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: .ok, headers: headers))), promise: nil)
            if head.method == .HEAD {
                finish(context, head: head)
            } else {
                writeDownload(remaining: total, context: context, head: head)
            }
        case "/stream":
            context.writeAndFlush(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: .ok, headers: HTTPHeaders([("X-Fixture", id), ("Content-Type", "text/plain")])))), promise: nil)
            writeTimed(["one\n", "two\n", "three\n"], every: .milliseconds(250), context: context, head: head)
        case "/sse":
            context.writeAndFlush(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: .ok, headers: HTTPHeaders([("X-Fixture", id), ("Content-Type", "text/event-stream"), ("Cache-Control", "no-cache")])))), promise: nil)
            writeTimed((1...3).map { "event: tick\ndata: \($0)\n\n" }, every: .milliseconds(150), context: context, head: head)
        case "/redirect":
            simple(context, head: head, status: .found, headers: [("Location", "/echo?from=redirect")])
        case "/cookie/set":
            simple(context, head: head, status: .ok, headers: [("Set-Cookie", "flavor=oatmeal; Path=/")])
        case "/cookie/get":
            json(context, head: head, ["cookie": head.headers.first(name: "cookie") ?? ""])
        default:
            simple(context, head: head, status: .notFound, headers: [])
        }
    }

    private func json(_ context: ChannelHandlerContext, head: HTTPRequestHead, _ object: [String: Any], extra: [(String, String)] = []) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        var headers = HTTPHeaders([("X-Fixture", id), ("Content-Type", "application/json"), ("Content-Length", String(data.count))])
        headers.add(contentsOf: extra)
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: .ok, headers: headers))), promise: nil)
        if head.method != .HEAD {
            context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: data)))), promise: nil)
        }
        finish(context, head: head)
    }

    private func simple(_ context: ChannelHandlerContext, head: HTTPRequestHead, status: HTTPResponseStatus, headers: [(String, String)]) {
        var all = HTTPHeaders([("X-Fixture", id), ("Content-Length", "0")])
        all.add(contentsOf: headers)
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status, headers: all))), promise: nil)
        finish(context, head: head)
    }

    private func finish(_ context: ChannelHandlerContext, head: HTTPRequestHead) {
        let done = context.writeAndFlush(wrapOutboundOut(.end(nil)))
        if !head.isKeepAlive {
            done.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
        }
    }

    /// Writes one chunk at a time, waiting for each to hit the socket, so the
    /// fixture itself never buffers the download.
    private func writeDownload(remaining: Int, context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard remaining > 0 else {
            finish(context, head: head)
            return
        }
        let size = min(1 << 16, remaining)
        var buffer = context.channel.allocator.buffer(capacity: size)
        buffer.writeRepeatingByte(UInt8(ascii: "x"), count: size)
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buffer)))).assumeIsolated().whenSuccess {
            // Writes can complete synchronously; hop through the loop so a
            // long download doesn't recurse off the end of the stack.
            context.eventLoop.execute {
                let (handler, context) = bound.value
                handler.writeDownload(remaining: remaining - size, context: context, head: head)
            }
        }
    }

    private func writeTimed(_ chunks: [String], every delay: TimeAmount, context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard let first = chunks.first else {
            finish(context, head: head)
            return
        }
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(string: first)))), promise: nil)
        let rest = Array(chunks.dropFirst())
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        context.eventLoop.scheduleTask(in: delay) {
            let (handler, context) = bound.value
            handler.writeTimed(rest, every: delay, context: context, head: head)
        }
    }
}

private final class WebSocketEchoHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    func handlerAdded(context: ChannelHandlerContext) {
        // Speak first, immediately after the 101: exercises bytes that arrive
        // in the same read as the upgrade response.
        send(.text, ByteBuffer(string: "hello"), context: context)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text:
            let text = String(buffer: frame.unmaskedData)
            if text == "close-me" {
                var reason = context.channel.allocator.buffer(capacity: 2)
                reason.write(webSocketErrorCode: .normalClosure)
                let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: reason)
                context.writeAndFlush(wrapOutboundOut(close)).assumeIsolated().whenComplete { _ in
                    context.close(promise: nil)
                }
            } else {
                send(.text, frame.unmaskedData, context: context)
            }
        case .binary:
            send(.binary, frame.unmaskedData, context: context)
        case .ping:
            send(.pong, frame.unmaskedData, context: context)
        case .connectionClose:
            let close = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(close)).assumeIsolated().whenComplete { _ in
                context.close(promise: nil)
            }
        default:
            break
        }
    }

    private func send(_ opcode: WebSocketOpcode, _ data: ByteBuffer, context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: opcode, data: data)), promise: nil)
    }
}
