import Foundation

/// The stable, machine-readable error codes the API returns. Agents branch on
/// these, so never rename one — add new cases instead.
public enum SubpanelErrorCode: String, Codable, Sendable, CaseIterable {
    case invalidName = "invalid_name"
    case reservedName = "reserved_name"
    case invalidTarget = "invalid_target"
    case nonLoopbackTarget = "non_loopback_target"
    case mappingNotFound = "mapping_not_found"
    case backendUnavailable = "backend_unavailable"
    case malformedJSON = "malformed_json"
    case invalidHost = "invalid_host"
    case notFound = "not_found"
    case methodNotAllowed = "method_not_allowed"
    case forbiddenOrigin = "forbidden_origin"
    case payloadTooLarge = "payload_too_large"
    case loopDetected = "loop_detected"
    case internalError = "internal_error"

    /// The HTTP status each code is served with.
    public var httpStatus: Int {
        switch self {
        case .invalidName, .invalidTarget, .nonLoopbackTarget, .malformedJSON: 400
        case .forbiddenOrigin: 403
        case .mappingNotFound, .notFound, .invalidHost: 404
        case .methodNotAllowed: 405
        case .reservedName: 409
        case .payloadTooLarge: 413
        case .internalError: 500
        case .backendUnavailable: 502
        case .loopDetected: 508
        }
    }
}

/// An error with a stable code and a message written for the agent or human
/// who has to fix it.
public struct SubpanelError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: SubpanelErrorCode
    public var message: String

    public init(_ code: SubpanelErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(code.rawValue): \(message)" }
}
