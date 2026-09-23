import CLaunch
import Darwin

/// launchd socket activation (plans/service-lifecycle.md).
///
/// The service's LaunchAgent plist declares `Sockets` for 127.0.0.1:80 and
/// [::1]:80. launchd — which runs as root — binds them and hands the
/// listening descriptors to the service, which itself runs as the user. That
/// is how Subpanel owns port 80 with no privileged helper and no root code.
public enum LaunchdSockets {
    public enum ActivationError: Error, CustomStringConvertible {
        /// Not started by launchd with a matching `Sockets` entry.
        case notManagedByLaunchd(name: String)
        case failed(name: String, errno: Int32)

        public var description: String {
            switch self {
            case .notManagedByLaunchd(let name):
                "launchd has no socket named '\(name)' for this process (was it started by launchd?)"
            case .failed(let name, let code):
                "launch_activate_socket(\(name)) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    /// The listening descriptors launchd created for the `Sockets` entry `name`.
    public static func activate(_ name: String) throws -> [CInt] {
        // launch_activate_socket's out-parameter isn't nullability-annotated.
        var fds = UnsafeMutablePointer<CInt>(bitPattern: 0)
        var count = 0
        let result = withUnsafeMutablePointer(to: &fds) { out in
            out.withMemoryRebound(to: UnsafeMutablePointer<CInt>.self, capacity: 1) {
                launch_activate_socket(name, $0, &count)
            }
        }
        guard result == 0 else {
            if result == ENOENT || result == ESRCH {
                throw ActivationError.notManagedByLaunchd(name: name)
            }
            throw ActivationError.failed(name: name, errno: result)
        }
        defer { free(fds) }
        guard let fds else { return [] }
        return Array(UnsafeBufferPointer(start: fds, count: count))
    }
}

extension LaunchdSockets {
    /// `127.0.0.1:80` / `[::1]:80` for a bound socket, via getsockname(2).
    public static func localAddress(of fd: CInt) -> String? {
        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let ok = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) == 0 }
        }
        guard ok else { return nil }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var service = [CChar](repeating: 0, count: Int(NI_MAXSERV))
        let result = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), &service, socklen_t(service.count), NI_NUMERICHOST | NI_NUMERICSERV)
            }
        }
        guard result == 0 else { return nil }
        func string(_ chars: [CChar]) -> String {
            String(decoding: chars.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        let address = string(host)
        let port = string(service)
        return address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}
