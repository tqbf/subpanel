import NIOCore

/// Sits in front of a backend connection's HTTP response decoder. It's a
/// pass-through until an upgrade (101) is accepted; then `hold()` makes it
/// queue further reads and the channel's EOF until `release()`.
///
/// Why: the decoder is removed a tick after the 101, and only forwards the
/// bytes it holds (a WebSocket frame sent with the 101) if it hasn't seen
/// EOF by then. A backend that sends a frame and hangs up at once would lose
/// the frame. Holding the EOF here lets the decoder hand its leftovers over
/// first; then the held events follow, in order (plans/proxy.md).
final class UpgradeGate: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = NIOAny

    private enum HeldEvent {
        case read(NIOAny)
        case readComplete
        case inactive
        case error(any Error)
    }

    private var holding = false
    private var held: [HeldEvent] = []
    private var context: ChannelHandlerContext?

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
    }

    func hold() {
        holding = true
    }

    /// Fires everything held, in order, and removes the gate.
    func release() {
        guard let context else { return }
        holding = false
        let events = held
        held = []
        for event in events {
            switch event {
            case .read(let data): context.fireChannelRead(data)
            case .readComplete: context.fireChannelReadComplete()
            case .inactive: context.fireChannelInactive()
            case .error(let error): context.fireErrorCaught(error)
            }
        }
        context.pipeline.syncOperations.removeHandler(context: context, promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if holding {
            held.append(.read(data))
        } else {
            context.fireChannelRead(data)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        if holding {
            held.append(.readComplete)
        } else {
            context.fireChannelReadComplete()
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if holding {
            held.append(.inactive)
        } else {
            context.fireChannelInactive()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        if holding {
            held.append(.error(error))
        } else {
            context.fireErrorCaught(error)
        }
    }
}
