import Foundation
import os

/// The authoritative registry: one actor owns every mapping.
///
/// Mutations persist first and commit to memory second, so memory and disk
/// never disagree; each commit publishes a fresh `RoutingTable` snapshot for
/// the proxy. Pass `store: nil` for an in-memory registry (tests).
public actor MappingRegistry {
    public enum PutResult: Sendable, Equatable {
        case created(AppMapping)
        case updated(AppMapping)
        case unchanged(AppMapping)

        public var mapping: AppMapping {
            switch self {
            case .created(let mapping), .updated(let mapping), .unchanged(let mapping): mapping
            }
        }
    }

    /// Lock-protected snapshot the proxy reads synchronously.
    public nonisolated let routes = RoutingTable()

    public nonisolated let registryURL: URL?
    private let store: RegistryStore?
    private var apps: [String: AppMapping] = [:]
    public private(set) var lastWrite: Date?
    public private(set) var loadWarning: String?

    private let log = Logger(subsystem: SubpanelConstants.logSubsystem, category: "registry")

    public init(store: RegistryStore?) {
        self.store = store
        self.registryURL = store?.url
    }

    /// Loads mappings from disk. Call once, before accepting traffic.
    public func load() {
        guard let store else { return }
        let result = store.load()
        apps = Dictionary(uniqueKeysWithValues: result.mappings.map { ($0.name, $0) })
        loadWarning = result.warning
        lastWrite = try? store.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let warning = result.warning {
            log.error("registry load: \(warning, privacy: .public)")
        } else {
            log.info("loaded \(self.apps.count) mapping(s) from \(store.url.path, privacy: .public)")
        }
        publish()
    }

    /// All mappings, sorted by name.
    public func all() -> [AppMapping] {
        apps.values.sorted { $0.name < $1.name }
    }

    public var count: Int { apps.count }

    public func mapping(named name: AppName) -> AppMapping? {
        apps[name.rawValue]
    }

    /// Creates or replaces a mapping. Idempotent: re-PUTting the same target
    /// is `.unchanged` and doesn't touch the disk.
    @discardableResult
    public func put(_ name: AppName, target: BackendTarget, now: Date = .now) throws -> PutResult {
        let result: PutResult
        if let existing = apps[name.rawValue] {
            if existing.target == target {
                return .unchanged(existing)
            }
            var updated = existing
            updated.targetHost = target.host
            updated.targetPort = target.port
            updated.updatedAt = now
            result = .updated(updated)
        } else {
            result = .created(AppMapping(name: name, target: target, createdAt: now, updatedAt: now))
        }

        var next = apps
        next[name.rawValue] = result.mapping
        try commit(next)
        switch result {
        case .created: log.info("created \(name.rawValue, privacy: .public) -> \(target.authority, privacy: .public)")
        case .updated: log.info("updated \(name.rawValue, privacy: .public) -> \(target.authority, privacy: .public)")
        case .unchanged: break
        }
        return result
    }

    /// Removes a mapping. Returns whether one existed.
    @discardableResult
    public func remove(_ name: AppName) throws -> Bool {
        guard apps[name.rawValue] != nil else { return false }
        var next = apps
        next[name.rawValue] = nil
        try commit(next)
        log.info("deleted \(name.rawValue, privacy: .public)")
        return true
    }

    private func commit(_ next: [String: AppMapping]) throws {
        if let store {
            do {
                try store.save(Array(next.values))
            } catch {
                log.error("registry save failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            lastWrite = .now
        }
        apps = next
        publish()
    }

    private func publish() {
        var table: [String: BackendTarget] = [:]
        for (name, mapping) in apps {
            table[name] = mapping.target
        }
        routes.publish(table)
    }
}
