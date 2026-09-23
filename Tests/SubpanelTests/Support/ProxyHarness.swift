import Foundation
import NIOCore
import NIOPosix
@testable import SubpanelCore
@testable import SubpanelServer

/// A real `ProxyServer` on an unprivileged port (both 127.0.0.1 and ::1, like
/// production), with an in-memory registry and a URLSession to drive it.
struct ProxyHarness {
    let registry: MappingRegistry
    let server: ProxyServer
    let port: Int
    let session: URLSession

    static func start() async throws -> ProxyHarness {
        let registry = MappingRegistry(store: nil)
        var lastError: (any Error)?
        for _ in 0..<10 {
            let port = try freePort()
            let info = ServiceInfo(version: "test", pid: getpid(), startedAt: .now, listeners: [], publicPort: port)
            let server = ProxyServer(
                routes: registry.routes,
                control: ControlAPI(registry: registry, info: info, prober: TCPReachabilityProber()),
                configuration: ProxyConfiguration(publicPort: port)
            )
            do {
                try await server.start([.bind(host: "127.0.0.1", port: port), .bind(host: "::1", port: port)])
                return ProxyHarness(registry: registry, server: server, port: port, session: makeSession())
            } catch {
                lastError = error
                await server.shutdown()
            }
        }
        throw lastError!
    }

    func stop() async {
        session.invalidateAndCancel()
        await server.shutdown()
    }

    /// `http://<name>.localhost:<port><path>`
    func url(_ name: String, _ path: String = "/") -> URL {
        URL(string: "http://\(name).localhost:\(port)\(path)")!
    }

    func register(_ name: String, _ target: String) async throws {
        try await registry.put(try AppName(validating: name), target: try BackendTarget(parsing: target))
    }

    func get(_ name: String, _ path: String, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(name, path))
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return try await send(request)
    }

    func send(_ request: URLRequest, delegate: (any URLSessionTaskDelegate)? = nil) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: delegate)
        return (data, response as! HTTPURLResponse)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }

    /// A port that is free right now on 127.0.0.1 (and very likely on ::1).
    static func freePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard bound else { throw POSIXError(.EADDRINUSE) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}

/// Speaks raw bytes to the proxy, for things URLSession won't do: pipelining,
/// HTTP/1.0, absolute-form targets, `Expect: 100-continue`.
enum RawClient {
    /// Sends `request` and returns everything received until the server closes
    /// the connection or `timeout` passes.
    static func exchange(port: Int, _ request: String, timeout: TimeAmount = .seconds(5)) async throws -> String {
        try await timeline(port: port, request, timeout: timeout).map(\.text).joined()
    }

    /// Like `exchange`, but keeps each read with the time it arrived.
    static func timeline(port: Int, _ request: String, timeout: TimeAmount = .seconds(5)) async throws -> [(at: ContinuousClock.Instant, text: String)] {
        let collector = NIOLockedValueBox<[(at: ContinuousClock.Instant, text: String)]>([])
        let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(Collector(box: collector))
                }
            }
            .connect(host: "127.0.0.1", port: port)
            .get()
        try await channel.writeAndFlush(ByteBuffer(string: request))
        let closed = channel.closeFuture
        let timer = channel.eventLoop.scheduleTask(in: timeout) { channel.close(promise: nil) }
        try? await closed.get()
        timer.cancel()
        return collector.withLockedValue { $0 }
    }

    private final class Collector: ChannelInboundHandler {
        typealias InboundIn = ByteBuffer
        let box: NIOLockedValueBox<[(at: ContinuousClock.Instant, text: String)]>

        init(box: NIOLockedValueBox<[(at: ContinuousClock.Instant, text: String)]>) {
            self.box = box
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let text = String(buffer: unwrapInboundIn(data))
            box.withLockedValue { $0.append((.now, text)) }
        }
    }
}

import NIOConcurrencyHelpers

/// Never follows redirects, so tests can see the backend's 3xx as-is.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
