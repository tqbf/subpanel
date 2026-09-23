import Foundation

/// One `name -> loopback HTTP endpoint` mapping — the whole data model.
public struct AppMapping: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var targetHost: String
    public var targetPort: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: AppName,
        target: BackendTarget,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name.rawValue
        self.targetHost = target.host
        self.targetPort = target.port
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Re-validates the stored fields. Used when loading from disk so a
    /// hand-edited or stale registry can't smuggle in a bad mapping.
    public func validated() throws(SubpanelError) -> (AppName, BackendTarget) {
        (try AppName(validating: name), try BackendTarget(host: targetHost, port: targetPort))
    }

    /// Non-throwing accessor for mappings that already came through `validated()`.
    public var target: BackendTarget? { try? BackendTarget(host: targetHost, port: targetPort) }
}
