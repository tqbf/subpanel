import Foundation
import Testing
@testable import SubpanelCore

/// Fixed answers for reachability, so API tests need no network.
struct StubProber: ReachabilityProbing {
    var reachablePorts: Set<Int> = []
    func isReachable(_ target: BackendTarget) async -> Bool { reachablePorts.contains(target.port) }
}

@Suite("Control API")
struct ControlAPITests {
    let registry = MappingRegistry(store: nil)
    var api: ControlAPI {
        ControlAPI(
            registry: registry,
            info: ServiceInfo(version: "1.2.3", pid: 42, startedAt: .now, listeners: ["127.0.0.1:80"], publicPort: 80),
            prober: StubProber(reachablePorts: [43127])
        )
    }

    func send(_ method: String, _ uri: String, body: String? = nil, headers: [String: String] = [:]) async -> LocalResponse {
        await api.handle(ControlRequest(method: method, uri: uri, headers: headers, body: Data((body ?? "").utf8)))
    }

    func json(_ response: LocalResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    func errorCode(_ response: LocalResponse) throws -> String? {
        (try json(response)["error"] as? [String: Any])?["code"] as? String
    }

    @Test func registerReadListUpdateDelete() async throws {
        // Register.
        var response = await send("PUT", "/api/v1/apps/wiki", body: #"{"target":"http://127.0.0.1:43127"}"#)
        #expect(response.status == 201)
        let created = try APICoding.decoder.decode(AppDTO.self, from: response.body)
        #expect(created == AppDTO(name: "wiki", url: "http://wiki.localhost", target: "http://127.0.0.1:43127", reachable: true))

        // Idempotent re-PUT.
        response = await send("PUT", "/api/v1/apps/wiki", body: #"{"target":"http://127.0.0.1:43127"}"#)
        #expect(response.status == 200)

        // Read.
        response = await send("GET", "/api/v1/apps/wiki")
        #expect(response.status == 200)
        #expect(try APICoding.decoder.decode(AppDTO.self, from: response.body).target == "http://127.0.0.1:43127")

        // Update.
        response = await send("PUT", "/api/v1/apps/wiki", body: #"{"target":"http://localhost:49281"}"#)
        #expect(response.status == 200)
        let updated = try APICoding.decoder.decode(AppDTO.self, from: response.body)
        #expect(updated.target == "http://localhost:49281")
        #expect(updated.reachable == false)

        // List.
        _ = await send("PUT", "/api/v1/apps/alpha", body: #"{"target":"http://[::1]:3000"}"#)
        response = await send("GET", "/api/v1/apps")
        let list = try APICoding.decoder.decode(AppListDTO.self, from: response.body)
        #expect(list.apps.map(\.name) == ["alpha", "wiki"])

        // Delete, twice: both 204.
        #expect(await send("DELETE", "/api/v1/apps/wiki").status == 204)
        #expect(await send("DELETE", "/api/v1/apps/wiki").status == 204)
        response = await send("GET", "/api/v1/apps/wiki")
        #expect(response.status == 404)
        #expect(try errorCode(response) == "mapping_not_found")
    }

    @Test func rejectsReservedAndInvalidNames() async throws {
        var response = await send("PUT", "/api/v1/apps/subpanel", body: #"{"target":"http://127.0.0.1:3000"}"#)
        #expect(response.status == 409)
        #expect(try errorCode(response) == "reserved_name")

        response = await send("PUT", "/api/v1/apps/My_App", body: #"{"target":"http://127.0.0.1:3000"}"#)
        #expect(response.status == 400)
        #expect(try errorCode(response) == "invalid_name")

        response = await send("GET", "/api/v1/apps/Foo")
        #expect(try errorCode(response) == "invalid_name")
    }

    @Test func rejectsBadTargetsAndBodies() async throws {
        var response = await send("PUT", "/api/v1/apps/x", body: #"{"target":"http://192.168.1.10:3000"}"#)
        #expect(response.status == 400)
        #expect(try errorCode(response) == "non_loopback_target")

        response = await send("PUT", "/api/v1/apps/x", body: #"{"target":"https://127.0.0.1:3000"}"#)
        #expect(try errorCode(response) == "invalid_target")

        response = await send("PUT", "/api/v1/apps/x", body: "{nope")
        #expect(response.status == 400)
        #expect(try errorCode(response) == "malformed_json")

        response = await send("PUT", "/api/v1/apps/x", body: #"{"port": 3000}"#)
        #expect(try errorCode(response) == "invalid_target")
        #expect(await registry.count == 0)
    }

    @Test func refusesMutationsFromWebPages() async throws {
        let response = await send(
            "PUT", "/api/v1/apps/x",
            body: #"{"target":"http://127.0.0.1:3000"}"#,
            headers: ["Origin": "http://evil.example"]
        )
        #expect(response.status == 403)
        #expect(try errorCode(response) == "forbidden_origin")
        #expect(await send("PUT", "/api/v1/apps/x", body: #"{"target":"http://127.0.0.1:3000"}"#, headers: ["Origin": "http://subpanel.localhost"]).status == 201)
    }

    @Test func methodAndPathErrors() async throws {
        var response = await send("POST", "/api/v1/apps")
        #expect(response.status == 405)
        #expect(response.header("Allow") == "GET, HEAD")
        #expect(try errorCode(response) == "method_not_allowed")

        response = await send("GET", "/api/v2/apps")
        #expect(response.status == 404)
        response = await send("GET", "/api/v1/nope")
        #expect(try errorCode(response) == "not_found")
    }

    @Test func statusAndDiscovery() async throws {
        _ = await send("PUT", "/api/v1/apps/wiki", body: #"{"target":"http://127.0.0.1:43127"}"#)
        let status = try APICoding.decoder.decode(StatusDTO.self, from: await send("GET", "/api/v1/status").body)
        #expect(status.status == "ok")
        #expect(status.version == "1.2.3")
        #expect(status.apiVersion == 1)
        #expect(status.mappingCount == 1)
        #expect(status.pid == 42)

        let discovery = try json(await send("GET", "/.well-known/subpanel"))
        #expect(discovery["api"] as? String == "http://subpanel.localhost/api/v1")
        #expect(discovery["instructions"] as? String == "http://subpanel.localhost/instructions")
        #expect(discovery["version"] as? Int == 1)
        let supports = try #require(discovery["supports"] as? [String: Bool])
        #expect(supports == ["http": true, "websocket": true, "https": false])
    }

    @Test("instructions are Markdown for agents", arguments: ["/instructions", "/instructions.md", "/llms.txt", "/"])
    func instructionsForAgents(_ path: String) async throws {
        let response = await send("GET", path, headers: ["Accept": "*/*"])
        #expect(response.status == 200)
        #expect(response.header("Content-Type") == "text/markdown; charset=utf-8")
        let text = String(decoding: response.body, as: UTF8.self)
        #expect(text.hasPrefix("# Subpanel"))
        #expect(text.contains("curl -sS -X PUT http://subpanel.localhost/api/v1/apps/myapp"))
        #expect(text.contains(AgentInstructions.convention))
    }

    @Test func browsersGetHTML() async throws {
        let accept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        var response = await send("GET", "/", headers: ["Accept": accept])
        #expect(response.header("Content-Type") == "text/html; charset=utf-8")
        #expect(String(decoding: response.body, as: UTF8.self).contains("Proxy running"))

        response = await send("GET", "/instructions", headers: ["Accept": accept])
        #expect(response.header("Content-Type") == "text/html; charset=utf-8")
        #expect(String(decoding: response.body, as: UTF8.self).contains("<h2>Give your app a URL</h2>"))

        // Markdown is always Markdown.
        response = await send("GET", "/instructions.md", headers: ["Accept": accept])
        #expect(response.header("Content-Type") == "text/markdown; charset=utf-8")

        // Fetchers that ask for Markdown get it even if they also take HTML.
        response = await send("GET", "/", headers: ["Accept": "text/markdown, text/html;q=0.9"])
        #expect(response.header("Content-Type") == "text/markdown; charset=utf-8")
    }

    @Test func instructionsUseTheDevPort() {
        let text = AgentInstructions.markdown(port: 8080)
        #expect(text.contains("http://subpanel.localhost:8080/api/v1/apps/myapp"))
        #expect(text.contains("http://myapp.localhost:8080"))
    }
}

@Suite("Markdown rendering")
struct MarkdownHTMLTests {
    @Test func blocks() {
        let html = MarkdownHTML.render("""
            # Title

            Para with `code` and **bold** and [a link](http://x.localhost/).

            - one
            - two

            3. third
            4. fourth

            ```sh
            echo "<hi>"
            ```

            > quoted
            """)
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains(#"<a href="http://x.localhost/">a link</a>"#))
        #expect(html.contains("<ul><li>one</li><li>two</li></ul>"))
        #expect(html.contains(#"<ol start="3"><li>third</li><li>fourth</li></ol>"#))
        #expect(html.contains("<pre><code>echo &quot;&lt;hi&gt;&quot;</code></pre>"))
        #expect(html.contains("<blockquote><p>quoted</p></blockquote>"))
    }

    @Test func autolinksAndEscapes() {
        #expect(MarkdownHTML.inline("see http://a.localhost/x.") == #"see <a href="http://a.localhost/x">http://a.localhost/x</a>."#)
        #expect(MarkdownHTML.inline("`http://a` <b>") == "<code>http://a</code> &lt;b&gt;")
    }

    @Test func rendersTheRealInstructions() {
        let html = MarkdownHTML.render(AgentInstructions.markdown())
        #expect(!html.contains("```"))
        #expect(!html.contains("**"))
        #expect(html.contains("<ol start=\"4\">"))
    }
}
