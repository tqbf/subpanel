import Darwin
import Foundation

/// A TCP socket in the LISTEN state, read from the OS socket table.
public struct SocketListener: Hashable, Sendable {
    /// The bound address: `127.0.0.1`, `::1`, or a wildcard (`0.0.0.0`, `::`).
    public var address: String
    public var port: Int
    public var pid: Int32
    /// The owning process's name, e.g. `node`.
    public var process: String

    public init(address: String, port: Int, pid: Int32, process: String) {
        self.address = address
        self.port = port
        self.pid = pid
        self.process = process
    }

    /// Whether a connection to `target` would land on this listener.
    /// Wildcard binds count; `::` also takes IPv4 (macOS's default is not
    /// IPV6_V6ONLY). `localhost` targets match either family, as routing
    /// tries both.
    public func accepts(_ target: BackendTarget) -> Bool {
        guard port == target.port else { return false }
        let ipv4 = ["127.0.0.1", "0.0.0.0", "::ffff:127.0.0.1", "::"]
        let ipv6 = ["::1", "::"]
        return switch target.host {
        case "127.0.0.1": ipv4.contains(address)
        case "::1": ipv6.contains(address)
        default: ipv4.contains(address) || ipv6.contains(address)
        }
    }
}

/// Reads which processes are listening on which TCP ports — the same data
/// `lsof -iTCP -sTCP:LISTEN` shows — via libproc. **It never connects to
/// anything**, so checking a backend can't disturb it or show up in its logs.
///
/// Sees the current user's processes (the only ones libproc will describe
/// without root). That covers dev servers, and Docker Desktop's published
/// ports; a backend running as another user reads as "not listening" even
/// though routing to it works.
public enum ListeningSockets {
    public static func scan() -> [SocketListener] {
        var listeners: [SocketListener] = []
        for pid in userProcesses() {
            for fd in socketDescriptors(of: pid) {
                if let listener = tcpListener(pid: pid, fd: fd) {
                    listeners.append(listener)
                }
            }
        }
        return listeners
    }

    private static func userProcesses() -> [pid_t] {
        let uid = UInt32(getuid())
        let needed = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard needed > 0 else { return [] }
        // Headroom for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 64)
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), uid, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return [] }
        return pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride).filter { $0 > 0 }
    }

    private static func socketDescriptors(of pid: pid_t) -> [Int32] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.stride + 16)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.stride))
        guard bytes > 0 else { return [] }
        return fds.prefix(Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
            .filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }
            .map(\.proc_fd)
    }

    private static func tcpListener(pid: pid_t, fd: Int32) -> SocketListener? {
        var info = socket_fdinfo()
        let size = Int32(MemoryLayout<socket_fdinfo>.size)
        guard proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
              info.psi.soi_kind == SOCKINFO_TCP
        else { return nil }
        let tcp = info.psi.soi_proto.pri_tcp
        guard tcp.tcpsi_state == TSI_S_LISTEN else { return nil }
        let endpoint = tcp.tcpsi_ini
        let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: endpoint.insi_lport)))
        let address: String
        if endpoint.insi_vflag & UInt8(INI_IPV4) != 0 {
            var ip = endpoint.insi_laddr.ina_46.i46a_addr4
            address = presentation(AF_INET, &ip)
        } else if endpoint.insi_vflag & UInt8(INI_IPV6) != 0 {
            var ip = endpoint.insi_laddr.ina_6
            address = presentation(AF_INET6, &ip)
        } else {
            return nil
        }
        return SocketListener(address: address, port: port, pid: pid, process: processName(pid))
    }

    private static func presentation(_ family: Int32, _ address: UnsafeRawPointer) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, address, &buffer, socklen_t(buffer.count)) != nil else { return "?" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Answers "is anything listening at this target, and who?" for the API.
public protocol ListenerLookup: Sendable {
    func listener(for target: BackendTarget) async -> SocketListener?
}

/// A `ListenerLookup` over `ListeningSockets.scan()`, rescanning at most
/// once per `maxAge` (a scan of a typical user's processes takes ~1 ms).
public actor ListenerIndex: ListenerLookup {
    private let maxAge: Duration
    private let scanner: @Sendable () -> [SocketListener]
    private var snapshot: [SocketListener] = []
    private var takenAt: ContinuousClock.Instant?

    public init(maxAge: Duration = .seconds(1), scanner: @escaping @Sendable () -> [SocketListener] = ListeningSockets.scan) {
        self.maxAge = maxAge
        self.scanner = scanner
    }

    public func listener(for target: BackendTarget) -> SocketListener? {
        let now = ContinuousClock.now
        if takenAt.map({ now - $0 >= maxAge }) ?? true {
            snapshot = scanner()
            takenAt = now
        }
        return snapshot.first { $0.accepts(target) }
    }
}
