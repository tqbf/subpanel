import NIOCore
import NIOPosix

/// A deliberately badly-behaved backend: waits for a request's headers, then
/// writes exactly `response` (any bytes at all) and optionally hangs up.
final class ScriptedBackend: Sendable {
    let channel: any Channel

    var port: Int { channel.localAddress!.port! }

    private init(channel: any Channel) {
        self.channel = channel
    }

    static func start(response: String, closeAfter: Bool) async throws -> ScriptedBackend {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(Script(response: response, closeAfter: closeAfter))
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        return ScriptedBackend(channel: channel)
    }

    func stop() async {
        try? await channel.close()
    }

    private final class Script: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        let response: String
        let closeAfter: Bool
        var received = ""
        var answered = false

        init(response: String, closeAfter: Bool) {
            self.response = response
            self.closeAfter = closeAfter
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            received += String(buffer: unwrapInboundIn(data))
            guard !answered, received.contains("\r\n\r\n") else { return }
            answered = true
            let written = context.writeAndFlush(NIOAny(ByteBuffer(string: response)))
            if closeAfter {
                written.assumeIsolated().whenComplete { _ in context.close(promise: nil) }
            }
        }
    }
}
