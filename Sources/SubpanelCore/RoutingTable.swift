import Foundation
import os

/// The proxy's read-side view of the registry: an immutable `name -> target`
/// snapshot, swapped atomically whenever the registry changes.
///
/// `MappingRegistry` is the single writer and the authority. NIO channel
/// handlers must route synchronously on their event loop and can't `await`
/// the actor, so the actor publishes each new snapshot here — the one lock in
/// the design, justified by that API boundary (plans/architecture.md).
/// A request looks its target up once and never holds the lock afterwards, so
/// a replaced mapping affects only *new* requests.
public final class RoutingTable: Sendable {
    private let snapshot = OSAllocatedUnfairLock(initialState: [String: BackendTarget]())

    public init() {}

    public func target(for name: String) -> BackendTarget? {
        snapshot.withLock { $0[name] }
    }

    public var count: Int {
        snapshot.withLock { $0.count }
    }

    func publish(_ table: [String: BackendTarget]) {
        snapshot.withLock { $0 = table }
    }
}

/// Where a request goes, decided purely from its `Host` header.
public enum HostRoute: Equatable, Sendable {
    /// `subpanel.localhost` — the control plane.
    case control
    /// `<name>.localhost` — a registered (or unregistered) app label.
    case app(String)
    /// Anything else: missing Host, IP literals, other domains, nested labels.
    case invalid(String?)

    /// Routes a raw `Host` header value. Case-insensitive, ignores any port and
    /// a trailing root dot. Does not validate the label against the registry.
    public init(hostHeader: String?) {
        guard let raw = hostHeader?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            self = .invalid(nil)
            return
        }
        var host = Substring(raw.lowercased())
        if host.hasPrefix("[") {
            self = .invalid(raw)  // IPv6 literal
            return
        }
        if let colon = host.lastIndex(of: ":") {
            host = host[..<colon]
        }
        if host.hasSuffix(".") {
            host = host.dropLast()
        }
        let suffix = ".\(SubpanelConstants.domain)"
        guard host.hasSuffix(suffix) else {
            self = .invalid(raw)
            return
        }
        let label = host.dropLast(suffix.count)
        guard !label.isEmpty, !label.contains(".") else {
            self = .invalid(raw)
            return
        }
        self = label == SubpanelConstants.controlLabel ? .control : .app(String(label))
    }
}
