import Foundation

/// The responses Subpanel generates on an app host instead of proxying:
/// unknown app, backend down, bad host, forwarding loop. Each is negotiated —
/// HTML for browsers, JSON for API clients, plain text for everything else
/// (curl) — and always says how to fix the problem.
public enum ProxyProblems {
    public static func noMapping(label: String, accept: String?, port: Int) -> LocalResponse {
        let host = "\(label).\(SubpanelConstants.domain)"
        let message = "No app is registered as \(host)."
        let register = registerCommand(label: label, port: port)
        return negotiate(
            error: SubpanelError(.mappingNotFound, "\(message) Register it with PUT \(SubpanelConstants.controlBaseURL(port: port))/api/v1/apps/\(label)."),
            accept: accept,
            port: port,
            title: "No app at \(host)",
            message: message,
            details: [],
            hint: "Register it with `\(register)`",
            text: "\(message)\n\nRegister it:\n  \(register)\n"
        )
    }

    public static func backendUnavailable(label: String, target: BackendTarget, accept: String?, port: Int) -> LocalResponse {
        let host = "\(label).\(SubpanelConstants.domain)"
        let message = "\(host) is registered, but its backend is unavailable."
        let register = registerCommand(label: label, port: port)
        return negotiate(
            error: SubpanelError(.backendUnavailable, "\(host) is registered, but its backend (\(target.authority)) is unavailable."),
            accept: accept,
            port: port,
            title: "\(host) is not responding",
            message: message,
            details: [("Target", target.authority)],
            hint: "Start the app. If it moved to another port, update the mapping with `\(register)`",
            text: "\(message)\n\nTarget: \(target.authority)\n\nStart the app. If it moved, update the mapping:\n  \(register)\n"
        )
    }

    public static func invalidHost(_ host: String?, accept: String?, port: Int) -> LocalResponse {
        let shown = host.map { "'\($0)'" } ?? "a request with no Host header"
        let message = "Subpanel serves only NAME.\(SubpanelConstants.domain) hosts, not \(shown)."
        let base = SubpanelConstants.controlBaseURL(port: port)
        return negotiate(
            error: SubpanelError(.invalidHost, "\(message) Subpanel itself is at \(base)/."),
            accept: accept,
            port: port,
            title: "Unknown host",
            message: message,
            details: [],
            hint: "Subpanel itself is at \(base)/",
            text: "\(message)\n\nSubpanel itself is at \(base)/\n"
        )
    }

    public static func loopDetected(label: String, accept: String?, port: Int) -> LocalResponse {
        let message = "Requests to \(label).\(SubpanelConstants.domain) are looping back through Subpanel."
        return negotiate(
            error: SubpanelError(.loopDetected, "\(message) Point the mapping at the app's own port, not at a .localhost URL."),
            accept: accept,
            port: port,
            title: "Forwarding loop",
            message: message,
            details: [],
            hint: "Point the mapping at the app's own port, not at a `.localhost` URL.",
            text: "\(message)\n\nPoint the mapping at the app's own port, not at a .localhost URL.\n"
        )
    }

    public static func payloadTooLarge(limit: Int) -> LocalResponse {
        .error(SubpanelError(.payloadTooLarge, "Control requests are limited to \(limit / 1024) KiB."))
    }

    private static func registerCommand(label: String, port: Int) -> String {
        let api = "\(SubpanelConstants.controlBaseURL(port: port))/api/v1/apps/\(label)"
        return #"curl -X PUT \#(api) -H 'Content-Type: application/json' -d '{"target":"http://127.0.0.1:PORT"}'"#
    }

    private static func negotiate(
        error: SubpanelError,
        accept: String?,
        port: Int,
        title: String,
        message: String,
        details: [(String, String)],
        hint: String,
        text: String
    ) -> LocalResponse {
        let status = error.code.httpStatus
        if Negotiation.prefersHTML(accept) {
            return .html(
                Pages.problem(title: title, message: message, details: details, hint: hint, port: port),
                status: status
            )
        }
        if Negotiation.prefersJSON(accept) {
            return .error(error)
        }
        let instructions = "\(SubpanelConstants.controlBaseURL(port: port))/instructions"
        return .text("\(text)\nAgent instructions: \(instructions)\n", status: status)
    }
}
