import Foundation

/// Fixed facts about Subpanel that every target agrees on.
///
/// Convention over configuration: there is exactly one control host, one
/// top-level domain, one registry location, and one launchd label.
public enum SubpanelConstants {
    /// The top-level domain every app lives under.
    public static let domain = "localhost"

    /// The label reserved for Subpanel's own control plane (`subpanel.localhost`).
    public static let controlLabel = "subpanel"

    /// `subpanel.localhost`.
    public static let controlHost = "\(controlLabel).\(domain)"

    /// Names an app may never take. `subpanel` is permanent; add others here
    /// (and to the agent instructions) only with a very good reason.
    public static let reservedNames: Set<String> = [controlLabel]

    /// The HTTP API version served under `/api/v1`.
    public static let apiVersion = 1

    /// The port Subpanel owns in production. Targets may not point here.
    public static let proxyPort = 80

    /// Bundle identifier of Subpanel.app, the full app.
    public static let appBundleIdentifier = "org.sockpuppet.subpanel"

    /// Bundle identifier of the menu-bar app, a login item bundled at
    /// `Subpanel.app/Contents/Library/LoginItems/SubpanelMenu.app`.
    public static let menuBundleIdentifier = "org.sockpuppet.subpanel.menu"

    /// launchd label of the proxy service (also the unified-logging subsystem).
    public static let serviceLabel = "org.sockpuppet.subpanel.service"

    /// Name of the LaunchAgent plist inside `Subpanel.app/Contents/Library/LaunchAgents`.
    public static let servicePlistName = "\(serviceLabel).plist"

    /// Names of the launchd `Sockets` entries the service activates.
    public static let launchdSocketNames = ["HTTP4", "HTTP6"]

    /// Unified-logging subsystem shared by the app and the service.
    public static let logSubsystem = "org.sockpuppet.subpanel"

    /// `~/Library/Application Support/Subpanel`.
    public static var supportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Subpanel", directoryHint: .isDirectory)
    }

    /// `~/Library/Application Support/Subpanel/registry.json` — the one
    /// persistent file. Only the service writes it.
    public static var defaultRegistryURL: URL {
        supportDirectory.appending(path: "registry.json", directoryHint: .notDirectory)
    }

    /// The base URL of the control plane for a proxy listening on `port`.
    /// Port 80 yields the canonical `http://subpanel.localhost`.
    public static func controlBaseURL(port: Int = proxyPort) -> String {
        "http://\(controlHost)\(portSuffix(port))"
    }

    /// The canonical user-facing URL of app `name` for a proxy on `port`.
    public static func appURL(name: String, port: Int = proxyPort) -> String {
        "http://\(name).\(domain)\(portSuffix(port))"
    }

    private static func portSuffix(_ port: Int) -> String {
        port == 80 ? "" : ":\(port)"
    }
}
