import Foundation

// Wire types for the `/api/v1` JSON API. Shared by the service (encoding) and
// the menu-bar app (decoding), so the two can't drift. See plans/api.md.

/// One mapping as the API presents it.
public struct AppDTO: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    /// The canonical user-facing URL, e.g. `http://wiki.localhost`.
    public var url: String
    /// The backend, e.g. `http://127.0.0.1:43127`.
    public var target: String
    /// Whether a TCP connection to the target succeeded moments ago. Advisory
    /// only — routing never consults it. `nil` when not probed.
    public var reachable: Bool?

    public var id: String { name }

    public init(name: String, url: String, target: String, reachable: Bool? = nil) {
        self.name = name
        self.url = url
        self.target = target
        self.reachable = reachable
    }
}

public struct AppListDTO: Codable, Sendable {
    public var apps: [AppDTO]

    public init(apps: [AppDTO]) {
        self.apps = apps
    }
}

/// Body of `PUT /api/v1/apps/:name`.
public struct PutAppBody: Codable, Sendable {
    public var target: String

    public init(target: String) {
        self.target = target
    }
}

/// `GET /api/v1/status`.
public struct StatusDTO: Codable, Sendable, Equatable {
    public var status: String
    public var version: String
    public var apiVersion: Int
    public var mappingCount: Int
    public var pid: Int32
    public var startedAt: Date
    public var uptimeSeconds: Int
    public var listeners: [String]
    public var registryPath: String?
    public var lastRegistryWrite: Date?
    public var registryWarning: String?

    public init(
        status: String,
        version: String,
        apiVersion: Int,
        mappingCount: Int,
        pid: Int32,
        startedAt: Date,
        uptimeSeconds: Int,
        listeners: [String],
        registryPath: String?,
        lastRegistryWrite: Date?,
        registryWarning: String?
    ) {
        self.status = status
        self.version = version
        self.apiVersion = apiVersion
        self.mappingCount = mappingCount
        self.pid = pid
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.listeners = listeners
        self.registryPath = registryPath
        self.lastRegistryWrite = lastRegistryWrite
        self.registryWarning = registryWarning
    }
}

/// `GET /.well-known/subpanel` — the capability document future clients inspect.
public struct DiscoveryDTO: Codable, Sendable {
    public struct Supports: Codable, Sendable {
        public var http: Bool
        public var websocket: Bool
        public var https: Bool
    }

    public var name: String
    public var version: Int
    public var serviceVersion: String
    public var api: String
    public var instructions: String
    public var supports: Supports
}

/// Every API error: `{"error":{"code":"invalid_name","message":"…"}}`.
public struct ErrorEnvelope: Codable, Sendable {
    public struct Body: Codable, Sendable {
        public var code: String
        public var message: String
    }

    public var error: Body

    public init(_ error: SubpanelError) {
        self.error = Body(code: error.code.rawValue, message: error.message)
    }
}

public enum APICoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
