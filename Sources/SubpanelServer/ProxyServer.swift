import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import os
import SubpanelCore

/// The listening side of Subpanel: accepts loopback connections and hands
/// each to a `ProxyHandler`.
public final class ProxyServer: Sendable {
    public enum Listener: Sendable, CustomStringConvertible {
        /// Bind this address ourselves (development and tests).
        case bind(host: String, port: Int)
        /// A listening socket launchd created for us (production, port 80).
        case descriptor(CInt)

        public var description: String {
            switch self {
            case .bind(let host, let port): host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
            case .descriptor(let fd): "launchd fd \(fd)"
            }
        }
    }

    public let routes: RoutingTable
    public let control: ControlAPI
    public let configuration: ProxyConfiguration
    private let group: any EventLoopGroup
    private let channels = NIOLockedValueBox<[any Channel]>([])
    private let log = Logger(subsystem: SubpanelConstants.logSubsystem, category: "proxy")

    public init(
        routes: RoutingTable,
        control: ControlAPI,
        configuration: ProxyConfiguration,
        group: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) {
        self.routes = routes
        self.control = control
        self.configuration = configuration
        self.group = group
    }

    /// Starts every listener; returns the addresses actually bound.
    @discardableResult
    public func start(_ listeners: [Listener]) async throws -> [SocketAddress] {
        var addresses: [SocketAddress] = []
        for listener in listeners {
            let channel: any Channel
            switch listener {
            case .bind(let host, let port):
                channel = try await bootstrap().bind(host: host, port: port).get()
            case .descriptor(let fd):
                channel = try await bootstrap().withBoundSocket(fd).get()
            }
            channels.withLockedValue { $0.append(channel) }
            if let address = channel.localAddress {
                addresses.append(address)
            }
            log.info("listening on \(channel.localAddress?.description ?? listener.description, privacy: .public)")
        }
        return addresses
    }

    /// Stops accepting. In-flight connections finish on their own.
    public func shutdown() async {
        let open = channels.withLockedValue { channels in
            defer { channels = [] }
            return channels
        }
        for channel in open {
            try? await channel.close()
        }
    }

    private func bootstrap() -> ServerBootstrap {
        let routes = routes
        let control = control
        let configuration = configuration
        return ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.socketOption(.tcp_nodelay), value: 1)
            .childChannelOption(.maxMessagesPerRead, value: 16)
            .childChannelInitializer { channel in
                // Defense in depth: we only ever bind loopback, but refuse
                // anything else even if a socket were somehow exposed.
                guard channel.remoteAddress?.isLoopback == true else {
                    return channel.close()
                }
                return channel.eventLoop.makeCompletedFuture {
                    let pipeline = channel.pipeline.syncOperations
                    try pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true, withErrorHandling: true)
                    try pipeline.addHandler(ProxyHandler(routes: routes, control: control, configuration: configuration))
                }
            }
    }
}

extension ProxyServer {
    /// Suspends until every listener has closed (i.e. after `shutdown()`).
    public func waitUntilClosed() async {
        for channel in channels.withLockedValue({ $0 }) {
            try? await channel.closeFuture.get()
        }
    }
}
