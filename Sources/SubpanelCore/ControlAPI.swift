import Foundation
import os

/// Checks whether a backend is accepting connections. Advisory only.
public protocol ReachabilityProbing: Sendable {
    func isReachable(_ target: BackendTarget) async -> Bool
}

/// Facts about the running service, fixed at startup.
public struct ServiceInfo: Sendable {
    public var version: String
    public var pid: Int32
    public var startedAt: Date
    /// Human-readable listener addresses, e.g. `127.0.0.1:80`.
    public var listeners: [String]
    /// The port clients use; 80 in production. Shapes every generated URL.
    public var publicPort: Int

    public init(version: String, pid: Int32, startedAt: Date, listeners: [String], publicPort: Int) {
        self.version = version
        self.pid = pid
        self.startedAt = startedAt
        self.listeners = listeners
        self.publicPort = publicPort
    }
}

/// Everything served on `subpanel.localhost`: the JSON API, the agent
/// instructions, discovery, and the status page. Pure request → response over
/// the registry, so it's tested without any networking (plans/api.md).
public struct ControlAPI: Sendable {
    public let registry: MappingRegistry
    public let info: ServiceInfo
    public let prober: (any ReachabilityProbing)?

    private let log = Logger(subsystem: SubpanelConstants.logSubsystem, category: "api")

    public init(registry: MappingRegistry, info: ServiceInfo, prober: (any ReachabilityProbing)? = nil) {
        self.registry = registry
        self.info = info
        self.prober = prober
    }

    private var base: String { SubpanelConstants.controlBaseURL(port: info.publicPort) }

    public func handle(_ request: ControlRequest) async -> LocalResponse {
        let path = request.path
        let method = request.method
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // Documents.
        switch path {
        case "/":
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            if Negotiation.prefersHTML(request.header("accept")) {
                return .html(Pages.status(await statusPage()))
            }
            return .markdown(AgentInstructions.markdown(port: info.publicPort))
        case "/instructions":
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            let markdown = AgentInstructions.markdown(port: info.publicPort)
            if Negotiation.prefersHTML(request.header("accept")) {
                return .html(Pages.instructions(markdown: markdown))
            }
            return .markdown(markdown)
        case "/instructions.md", "/llms.txt":
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            return .markdown(AgentInstructions.markdown(port: info.publicPort))
        case "/.well-known/subpanel":
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            return .json(discovery)
        default:
            break
        }

        // The JSON API.
        guard segments.count >= 2, segments[0] == "api", segments[1] == "v\(SubpanelConstants.apiVersion)" else {
            return notFound(request)
        }
        switch Array(segments.dropFirst(2)) {
        case ["status"]:
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            return .json(await status())
        case ["apps"]:
            guard isRead(method) else { return methodNotAllowed(["GET", "HEAD"]) }
            return .json(AppListDTO(apps: await dtos(for: registry.all())))
        case let rest where rest.count == 2 && rest[0] == "apps":
            return await handleApp(rawName: rest[1], request: request)
        default:
            return .error(SubpanelError(.notFound, "No API endpoint at \(path). See \(base)/instructions."))
        }
    }

    // MARK: - /api/v1/apps/:name

    private func handleApp(rawName: String, request: ControlRequest) async -> LocalResponse {
        let method = request.method
        guard isRead(method) || method == "PUT" || method == "DELETE" else {
            return methodNotAllowed(["GET", "HEAD", "PUT", "DELETE"])
        }
        if method == "PUT" || method == "DELETE", let origin = request.header("origin"), origin != base {
            log.error("refused \(method, privacy: .public) from origin \(origin, privacy: .public)")
            return .error(SubpanelError(.forbiddenOrigin, "Web pages may not change Subpanel mappings."))
        }

        let name: AppName
        do {
            name = try AppName(validating: rawName)
        } catch {
            log.info("rejected name '\(rawName, privacy: .public)': \(error.code.rawValue, privacy: .public)")
            return .error(error)
        }

        switch method {
        case "PUT":
            return await put(name, body: request.body)
        case "DELETE":
            do {
                try await registry.remove(name)
                return .noContent()
            } catch {
                return .error(SubpanelError(.internalError, "Couldn't save the registry: \(error.localizedDescription)"))
            }
        default:
            guard let mapping = await registry.mapping(named: name) else {
                return .error(SubpanelError(
                    .mappingNotFound,
                    "No app named '\(name)'. Register it with PUT \(base)/api/v1/apps/\(name)."
                ))
            }
            return .json(await dto(for: mapping))
        }
    }

    private func put(_ name: AppName, body: Data) async -> LocalResponse {
        let example = #"Send JSON like {"target":"http://127.0.0.1:5173"}."#
        let payload: PutAppBody
        do {
            payload = try JSONDecoder().decode(PutAppBody.self, from: body)
        } catch DecodingError.keyNotFound, DecodingError.typeMismatch, DecodingError.valueNotFound {
            return .error(SubpanelError(.invalidTarget, "The body needs a string \"target\". \(example)"))
        } catch {
            log.info("malformed JSON for PUT \(name.rawValue, privacy: .public)")
            return .error(SubpanelError(.malformedJSON, "The request body isn't valid JSON. \(example)"))
        }

        let target: BackendTarget
        do {
            target = try BackendTarget(parsing: payload.target)
        } catch {
            log.info("rejected target '\(payload.target, privacy: .public)' for \(name.rawValue, privacy: .public)")
            return .error(error)
        }

        do {
            let result = try await registry.put(name, target: target)
            let status = if case .created = result { 201 } else { 200 }
            return .json(await dto(for: result.mapping), status: status)
        } catch {
            return .error(SubpanelError(.internalError, "Couldn't save the registry: \(error.localizedDescription)"))
        }
    }

    // MARK: - Documents & DTOs

    private var discovery: DiscoveryDTO {
        DiscoveryDTO(
            name: "Subpanel",
            version: SubpanelConstants.apiVersion,
            serviceVersion: info.version,
            api: "\(base)/api/v\(SubpanelConstants.apiVersion)",
            instructions: "\(base)/instructions",
            supports: .init(http: true, websocket: true, https: false)
        )
    }

    public func status() async -> StatusDTO {
        StatusDTO(
            status: "ok",
            version: info.version,
            apiVersion: SubpanelConstants.apiVersion,
            mappingCount: await registry.count,
            pid: info.pid,
            startedAt: info.startedAt,
            uptimeSeconds: max(0, Int(Date.now.timeIntervalSince(info.startedAt))),
            listeners: info.listeners,
            registryPath: registry.registryURL?.path,
            lastRegistryWrite: await registry.lastWrite,
            registryWarning: await registry.loadWarning
        )
    }

    private func statusPage() async -> Pages.Status {
        Pages.Status(version: info.version, apps: await dtos(for: registry.all()), port: info.publicPort)
    }

    private func dto(for mapping: AppMapping) async -> AppDTO {
        var dto = AppDTO(
            name: mapping.name,
            url: SubpanelConstants.appURL(name: mapping.name, port: info.publicPort),
            target: mapping.target?.urlString ?? ""
        )
        if let prober, let target = mapping.target {
            dto.reachable = await prober.isReachable(target)
        }
        return dto
    }

    private func dtos(for mappings: [AppMapping]) async -> [AppDTO] {
        await withTaskGroup(of: (Int, AppDTO).self) { group in
            for (index, mapping) in mappings.enumerated() {
                group.addTask { (index, await dto(for: mapping)) }
            }
            var results = [AppDTO?](repeating: nil, count: mappings.count)
            for await (index, dto) in group {
                results[index] = dto
            }
            return results.compactMap { $0 }
        }
    }

    // MARK: - Helpers

    private func isRead(_ method: String) -> Bool { method == "GET" || method == "HEAD" }

    private func methodNotAllowed(_ allowed: [String]) -> LocalResponse {
        var response = LocalResponse.error(SubpanelError(
            .methodNotAllowed,
            "Allowed methods here: \(allowed.joined(separator: ", "))."
        ))
        response.headers.append(("Allow", allowed.joined(separator: ", ")))
        return response
    }

    private func notFound(_ request: ControlRequest) -> LocalResponse {
        let message = "Nothing at \(request.path) on \(SubpanelConstants.controlHost)."
        if Negotiation.prefersHTML(request.header("accept")) {
            return .html(
                Pages.problem(title: "Not found", message: message, port: info.publicPort),
                status: 404
            )
        }
        return .error(SubpanelError(.notFound, "\(message) Agent instructions: \(base)/instructions"))
    }
}
