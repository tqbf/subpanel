import Foundation

/// A validated backend: plain HTTP on a loopback address, explicit port.
///
/// Only `127.0.0.1`, `::1` and `localhost` are accepted — structurally, not by
/// resolving anything — so Subpanel can never be used as a localhost-to-network
/// proxy (plans/registry.md).
public struct BackendTarget: Hashable, Codable, Sendable, CustomStringConvertible {
    /// `127.0.0.1`, `::1`, or `localhost` (lowercased, no brackets).
    public let host: String
    public let port: Int

    public static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    public init(host: String, port: Int) throws(SubpanelError) {
        let host = host.lowercased()
        guard Self.loopbackHosts.contains(host) else {
            throw SubpanelError(
                .nonLoopbackTarget,
                "Targets must be on loopback (127.0.0.1, [::1], or localhost), not '\(host)'."
            )
        }
        guard (1...65_535).contains(port) else {
            throw SubpanelError(.invalidTarget, "Port \(port) is out of range.")
        }
        guard port != SubpanelConstants.proxyPort else {
            throw SubpanelError(
                .invalidTarget,
                "Port 80 is Subpanel's own listener. Bind your app to a free high port and register that."
            )
        }
        self.host = host
        self.port = port
    }

    /// Parses the API's `target` string, e.g. `http://127.0.0.1:5173`.
    public init(parsing string: String) throws(SubpanelError) {
        let example = "Use a URL like http://127.0.0.1:5173."
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
            throw SubpanelError(.invalidTarget, "'\(string)' is not a URL. \(example)")
        }
        guard scheme == "http" else {
            if scheme == "https" {
                throw SubpanelError(
                    .invalidTarget,
                    "HTTPS backends aren't supported. Serve plain HTTP on loopback. \(example)"
                )
            }
            throw SubpanelError(.invalidTarget, "Targets must use http://. \(example)")
        }
        guard components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            throw SubpanelError(.invalidTarget, "A target is just http://HOST:PORT, with no path or query. \(example)")
        }
        guard var host = components.host, !host.isEmpty else {
            throw SubpanelError(.invalidTarget, "'\(string)' has no host. \(example)")
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard let port = components.port else {
            throw SubpanelError(.invalidTarget, "Include the port explicitly. \(example)")
        }
        try self.init(host: host, port: port)
    }

    /// The canonical URL form: `http://127.0.0.1:5173`, `http://[::1]:5173`.
    public var urlString: String { "http://\(authority)" }

    /// `127.0.0.1:5173` or `[::1]:5173`.
    public var authority: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    public var description: String { authority }

    // Codable as the URL string so the wire and disk forms read naturally.
    public init(from decoder: any Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(parsing: string)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: error.message))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(urlString)
    }
}
