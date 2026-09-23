import Foundation

/// Why a call to the Subpanel service failed, phrased for the person who
/// has to act on it.
public enum ClientError: LocalizedError, Equatable {
    /// The service answered with a structured API error.
    case api(code: String, message: String)
    /// Nothing answered at `subpanel.localhost` (service stopped or starting).
    case unreachable(String)
    /// The service answered with something we didn't expect.
    case unexpected(status: Int)

    public var errorDescription: String? {
        switch self {
        case .api(_, let message): message
        case .unreachable(let detail): "Subpanel's service isn't responding (\(detail))."
        case .unexpected(let status): "Subpanel's service returned an unexpected response (HTTP \(status))."
        }
    }
}
