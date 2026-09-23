import Foundation

/// The apps' only channel to the service (both Subpanel.app and the menu-bar
/// app): the same loopback HTTP API agents use (plans/architecture.md,
/// "IPC"). Neither app ever touches the registry file itself.
public struct SubpanelClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    /// `http://subpanel.localhost`, unless overridden for development with the
    /// `SUBPANEL_BASE_URL` environment variable or the `SubpanelBaseURL`
    /// default (e.g. `http://subpanel.localhost:8080`).
    public static func standard() -> SubpanelClient {
        let override = ProcessInfo.processInfo.environment["SUBPANEL_BASE_URL"]
            ?? UserDefaults.standard.string(forKey: "SubpanelBaseURL")
        let fallback = URL(string: SubpanelConstants.controlBaseURL())
        guard let baseURL = override.flatMap(URL.init(string:)) ?? fallback else {
            fatalError("The built-in Subpanel base URL is malformed")
        }
        return SubpanelClient(baseURL: baseURL)
    }

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.urlCache = nil
        // Never route loopback calls through a system HTTP proxy.
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    public var instructionsURL: URL { baseURL.appending(path: "instructions") }

    public func status() async throws -> StatusDTO {
        try await decode(StatusDTO.self, from: request("GET", "api/v1/status"))
    }

    public func apps() async throws -> [AppDTO] {
        try await decode(AppListDTO.self, from: request("GET", "api/v1/apps")).apps
    }

    public func put(name: String, target: String) async throws -> AppDTO {
        let body = try JSONEncoder().encode(PutAppBody(target: target))
        return try await decode(AppDTO.self, from: request("PUT", "api/v1/apps/\(name)", body: body))
    }

    public func delete(name: String) async throws {
        _ = try await request("DELETE", "api/v1/apps/\(name)")
    }

    // MARK: - Plumbing

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                throw ClientError.api(code: envelope.error.code, message: envelope.error.message)
            }
            throw ClientError.unexpected(status: status)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try APICoding.decoder.decode(type, from: data)
        } catch {
            throw ClientError.unexpected(status: 200)
        }
    }
}
