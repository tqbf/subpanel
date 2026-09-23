import NIOCore
import NIOHTTP1
import SubpanelCore

/// Header rewriting for the reverse proxy (plans/proxy.md, "Headers").
///
/// Pure functions over NIO heads, so every rule here is unit-tested without
/// sockets.
enum ProxyHeaders {
    /// RFC 9110 §7.6.1 hop-by-hop headers, plus the legacy `Proxy-Connection`.
    /// Any header *named* in `Connection` is hop-by-hop too.
    static let hopByHop: Set<String> = [
        "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
        "te", "trailer", "transfer-encoding", "upgrade", "proxy-connection",
    ]

    /// How many times a request may pass through Subpanel before it's
    /// declared a loop. More than one is legitimate: an app on one name can
    /// call an app on another through Subpanel.
    static let maxHops = 8

    static let viaToken = "1.1 subpanel"

    static func removeHopByHop(_ headers: inout HTTPHeaders) {
        let named = headers[canonicalForm: "connection"].map { String($0).lowercased() }
        for name in hopByHop.union(named) {
            headers.remove(name: name)
        }
    }

    /// A WebSocket-style upgrade: `Connection: upgrade` plus an `Upgrade` header.
    static func isUpgradeRequest(_ head: HTTPRequestHead) -> Bool {
        head.headers[canonicalForm: "connection"].contains { $0.lowercased() == "upgrade" }
            && head.headers.contains(name: "upgrade")
    }

    static func hopCount(_ head: HTTPRequestHead) -> Int {
        head.headers[canonicalForm: "via"].filter { $0.lowercased().hasSuffix("subpanel") }.count
    }

    /// Splits an absolute-form request target (`GET http://wiki.localhost/x`)
    /// into the authority and an origin-form target. Returns nil otherwise.
    static func splitAbsoluteForm(_ uri: String) -> (authority: String, uri: String)? {
        guard uri.lowercased().hasPrefix("http://") else { return nil }
        let rest = uri.dropFirst("http://".count)
        let slash = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        let authority = String(rest[..<slash])
        var target = String(rest[slash...])
        if target.isEmpty { target = "/" }
        if target.hasPrefix("?") { target = "/" + target }
        return (authority, target)
    }

    /// The head sent to the backend.
    ///
    /// Preserves method, target, and ordinary headers — including the
    /// original `Host` (`wiki.localhost`), which dev servers use to build
    /// origin-aware URLs. Strips hop-by-hop headers, re-adds `Upgrade` for
    /// upgrades, keeps chunked framing, and sets the forwarding headers.
    static func backendHead(
        for head: HTTPRequestHead,
        uri: String,
        host: String,
        clientAddress: String?
    ) -> HTTPRequestHead {
        var headers = head.headers
        let upgrade = isUpgradeRequest(head) ? headers["upgrade"].joined(separator: ", ") : nil
        let chunked = headers[canonicalForm: "transfer-encoding"].contains { $0.lowercased() == "chunked" }
        removeHopByHop(&headers)

        if let upgrade {
            headers.add(name: "Connection", value: "Upgrade")
            headers.add(name: "Upgrade", value: upgrade)
        } else {
            // One backend connection per request (plans/proxy.md).
            headers.add(name: "Connection", value: "close")
        }
        if chunked, !headers.contains(name: "content-length") {
            headers.add(name: "Transfer-Encoding", value: "chunked")
        }
        // For absolute-form targets the URI's authority wins (RFC 9112 §3.2.2).
        headers.replaceOrAdd(name: "Host", value: host)

        let client = clientAddress ?? "127.0.0.1"
        let forwardedFor = client.contains(":") ? "\"[\(client)]\"" : client
        headers.replaceOrAdd(name: "X-Forwarded-For", value: client)
        headers.replaceOrAdd(name: "X-Forwarded-Host", value: host)
        headers.replaceOrAdd(name: "X-Forwarded-Proto", value: "http")
        headers.replaceOrAdd(name: "Forwarded", value: "for=\(forwardedFor);host=\(host);proto=http")
        headers.add(name: "Via", value: viaToken)

        var backend = HTTPRequestHead(version: .http1_1, method: head.method, uri: uri)
        backend.headers = headers
        return backend
    }

    /// The head sent back to the client. Framing is left to NIO's encoder,
    /// which re-frames the body (chunked when the length is unknown).
    static func clientHead(
        for response: HTTPResponseHead,
        requestVersion: HTTPVersion,
        closeAfter: Bool,
        upgrade: Bool
    ) -> HTTPResponseHead {
        var headers = response.headers
        let upgradeValue = headers["upgrade"].joined(separator: ", ")
        removeHopByHop(&headers)
        if upgrade {
            headers.add(name: "Connection", value: "Upgrade")
            headers.add(name: "Upgrade", value: upgradeValue)
        } else if closeAfter {
            headers.add(name: "Connection", value: "close")
        }
        return HTTPResponseHead(version: requestVersion, status: response.status, headers: headers)
    }
}

extension SocketAddress {
    /// True for 127.0.0.0/8, ::1, and IPv4-mapped loopback.
    var isLoopback: Bool {
        switch self {
        case .v4(let address):
            return UInt32(bigEndian: address.address.sin_addr.s_addr) >> 24 == 127
        case .v6:
            guard let ip = ipAddress?.lowercased() else { return false }
            return ip == "::1" || ip.hasPrefix("::ffff:127.")
        case .unixDomainSocket:
            return false
        }
    }
}
