import Darwin
import Foundation
import Testing
@testable import SubpanelCore

/// A real listening socket owned by this test process.
private struct TestListener: ~Copyable {
    let fd: Int32
    let port: Int

    init(ipv6: Bool) throws {
        let socketFD = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        var length: socklen_t
        let ok: Bool
        let boundPort: Int
        if ipv6 {
            var address = sockaddr_in6()
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_addr = in6addr_loopback
            length = socklen_t(MemoryLayout<sockaddr_in6>.size)
            ok = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, length) == 0 && getsockname(socketFD, $0, &length) == 0 }
            }
            boundPort = Int(UInt16(bigEndian: address.sin6_port))
        } else {
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            length = socklen_t(MemoryLayout<sockaddr_in>.size)
            ok = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, length) == 0 && getsockname(socketFD, $0, &length) == 0 }
            }
            boundPort = Int(UInt16(bigEndian: address.sin_port))
        }
        guard ok, listen(socketFD, 1) == 0 else {
            close(socketFD)
            throw POSIXError(.EADDRINUSE)
        }
        fd = socketFD
        port = boundPort
    }

    deinit {
        close(fd)
    }
}

@Suite("Listening sockets")
struct ListeningSocketsTests {
    @Test("finds this process's own listeners, without connecting", arguments: [false, true])
    func findsOwnListener(ipv6: Bool) throws {
        let listener = try TestListener(ipv6: ipv6)
        let found = ListeningSockets.scan().filter { $0.port == listener.port }
        let mine = try #require(found.first)
        #expect(mine.pid == getpid())
        #expect(mine.address == (ipv6 ? "::1" : "127.0.0.1"))
        #expect(!mine.process.isEmpty)
    }

    @Test func closedPortIsNotListening() throws {
        let port: Int
        do {
            let listener = try TestListener(ipv6: false)
            port = listener.port
        }
        #expect(!ListeningSockets.scan().contains { $0.port == port })
    }

    @Test("matching a target to a listener", arguments: [
        ("127.0.0.1", "127.0.0.1", true),
        ("127.0.0.1", "0.0.0.0", true),
        ("127.0.0.1", "::", true),        // dual-stack wildcard
        ("127.0.0.1", "::1", false),
        ("::1", "::1", true),
        ("::1", "::", true),
        ("::1", "127.0.0.1", false),
        ("::1", "0.0.0.0", false),
        ("localhost", "::1", true),
        ("localhost", "127.0.0.1", true),
        ("localhost", "192.168.1.5", false),
    ])
    func matching(targetHost: String, listenerAddress: String, expected: Bool) throws {
        let target = try BackendTarget(host: targetHost, port: 5173)
        #expect(SocketListener(address: listenerAddress, port: 5173, pid: 1, process: "node").accepts(target) == expected)
        #expect(!SocketListener(address: listenerAddress, port: 5174, pid: 1, process: "node").accepts(target))
    }

    @Test func indexCachesScans() async throws {
        let scans = ScanCounter()
        let index = ListenerIndex(maxAge: .seconds(60)) {
            scans.bump()
            return [SocketListener(address: "127.0.0.1", port: 3000, pid: 7, process: "ruby")]
        }
        let target = try BackendTarget(host: "127.0.0.1", port: 3000)
        #expect(await index.listener(for: target)?.process == "ruby")
        #expect(await index.listener(for: try BackendTarget(host: "::1", port: 3000)) == nil)
        #expect(scans.count == 1)
    }
}

private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func bump() { lock.withLock { value += 1 } }
}
