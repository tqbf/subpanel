import NIOCore
import NIOHTTP1

/// Sits at the end of a backend connection's pipeline and relays the
/// response to the `ProxyHandler` that opened it. Both channels share one
/// event loop, so every call here is synchronous and lock-free.
final class BackendHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundIn = HTTPClientRequestPart
    typealias OutboundOut = HTTPClientRequestPart

    private var proxy: ProxyHandler?
    private let exchange: ProxyExchange
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    init(proxy: ProxyHandler, exchange: ProxyExchange) {
        self.proxy = proxy
        self.exchange = exchange
    }

    /// Stops relaying: the exchange is over (or upgraded to a raw tunnel).
    func detach() {
        proxy = nil
    }

    var isWritable: Bool {
        context?.channel.isWritable ?? false
    }

    func send(_ part: HTTPClientRequestPart) {
        context?.write(wrapOutboundOut(part), promise: nil)
    }

    func flush() {
        context?.flush()
    }

    /// The client drained its outbound buffer: resume reading the response.
    func clientBecameWritable() {
        if pendingRead {
            pendingRead = false
            context?.read()
        }
    }

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        proxy?.backendReceived(unwrapInboundIn(data), exchange: exchange)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        proxy?.backendReadComplete(exchange: exchange)
        context.fireChannelReadComplete()
    }

    func channelInactive(context: ChannelHandlerContext) {
        proxy?.backendClosed(exchange: exchange, channel: context.channel)
        context.fireChannelInactive()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            proxy?.backendBecameWritable(exchange: exchange)
        }
        context.fireChannelWritabilityChanged()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        // A malformed response, reset, etc. Closing surfaces it to the proxy
        // through channelInactive: 502 if nothing was sent yet, else truncate.
        context.close(promise: nil)
    }

    // Backpressure: only read more of the response while the client can take it.
    func read(context: ChannelHandlerContext) {
        if let proxy, !proxy.clientIsWritable {
            pendingRead = true
        } else {
            context.read()
        }
    }
}
