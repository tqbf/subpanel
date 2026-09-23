import Foundation
import Testing
@testable import SubpanelCore
@testable import SubpanelServer

/// End-to-end: URLSession (or raw sockets) → ProxyServer → BackendFixture.
@Suite("Proxy", .serialized)
struct ProxyIntegrationTests {
    /// Runs `body` with a proxy and a fixture registered as `fixture.localhost`.
    func withProxy(_ body: (ProxyHarness, BackendFixture) async throws -> Void) async throws {
        let proxy = try await ProxyHarness.start()
        let fixture = try await BackendFixture.start()
        try await proxy.register("fixture", "http://127.0.0.1:\(fixture.port)")
        do {
            try await body(proxy, fixture)
        } catch {
            await fixture.stop()
            await proxy.stop()
            throw error
        }
        await fixture.stop()
        await proxy.stop()
    }

    func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func headers(_ echo: [String: Any]) -> [String: String] {
        let pairs = echo["headers"] as? [[String]] ?? []
        return Dictionary(pairs.map { ($0[0], $0[1]) }, uniquingKeysWith: { "\($0), \($1)" })
    }

    // MARK: - Plain HTTP

    @Test func getPreservesMethodPathQueryAndHeaders() async throws {
        try await withProxy { proxy, _ in
            let (data, response) = try await proxy.get("fixture", "/echo?a=1&b=two%20words", headers: ["X-Custom": "yes"])
            #expect(response.statusCode == 200)
            #expect(response.value(forHTTPHeaderField: "X-Echo") == "yes")  // response headers pass back
            let echo = try object(data)
            #expect(echo["method"] as? String == "GET")
            #expect(echo["uri"] as? String == "/echo?a=1&b=two%20words")
            let sent = headers(echo)
            let host = "fixture.localhost:\(proxy.port)"
            #expect(sent["host"] == host)  // original Host preserved
            #expect(sent["x-custom"] == "yes")
            #expect(sent["x-forwarded-host"] == host)
            #expect(sent["x-forwarded-proto"] == "http")
            #expect(["127.0.0.1", "::1"].contains(sent["x-forwarded-for"] ?? ""))
            #expect(sent["forwarded"]?.contains("host=\(host);proto=http") == true)
            #expect(sent["via"] == "1.1 subpanel")
            #expect(sent["connection"] == "close")
            #expect(sent["keep-alive"] == nil)
        }
    }

    @Test func postBody() async throws {
        try await withProxy { proxy, _ in
            var request = URLRequest(url: proxy.url("fixture", "/echo"))
            request.httpMethod = "POST"
            request.httpBody = Data("hello, backend".utf8)
            let (data, _) = try await proxy.send(request)
            let echo = try object(data)
            #expect(echo["method"] as? String == "POST")
            #expect(echo["body"] as? String == "hello, backend")
            #expect(echo["bodyLength"] as? Int == 14)
        }
    }

    @Test func largeUploadWithContentLength() async throws {
        try await withProxy { proxy, _ in
            let size = 32 << 20
            var request = URLRequest(url: proxy.url("fixture", "/upload"))
            request.httpMethod = "PUT"
            let (data, response) = try await proxy.session.upload(for: request, from: Data(count: size))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(try object(data)["bytes"] as? Int == size)
        }
    }

    @Test func largeChunkedUpload() async throws {
        try await withProxy { proxy, _ in
            let size = 8 << 20
            var request = URLRequest(url: proxy.url("fixture", "/upload"))
            request.httpMethod = "POST"
            request.httpBodyStream = InputStream(data: Data(count: size))  // no length: chunked
            let (data, _) = try await proxy.send(request)
            #expect(try object(data)["bytes"] as? Int == size)
        }
    }

    @Test("large download", arguments: ["", "&chunked=1"])
    func largeDownload(_ variant: String) async throws {
        try await withProxy { proxy, _ in
            let size = 48 << 20
            let (data, response) = try await proxy.get("fixture", "/download?bytes=\(size)\(variant)")
            #expect(response.statusCode == 200)
            #expect(data.count == size)
            #expect(data.allSatisfy { $0 == UInt8(ascii: "x") })
        }
    }

    @Test("streaming responses are relayed as they're produced", arguments: ["/stream", "/sse"])
    func streamingIsNotBuffered(_ path: String) async throws {
        try await withProxy { proxy, _ in
            // Raw socket: URLSession sniffs content and would buffer small chunks.
            let reads = try await RawClient.timeline(port: proxy.port, "GET \(path) HTTP/1.1\r\nHost: fixture.localhost\r\nConnection: close\r\n\r\n")
            let text = reads.map(\.text).joined()
            #expect(text.contains(path == "/stream" ? "three" : "data: 3"))
            // The backend spaces its chunks ≥150 ms apart; relayed promptly,
            // they can't all land in one read.
            let first = try #require(reads.first?.at)
            let last = try #require(reads.last?.at)
            #expect(reads.count >= 3)
            #expect(last - first > .milliseconds(250))
        }
    }

    @Test func serverSentEvents() async throws {
        try await withProxy { proxy, _ in
            let (bytes, response) = try await proxy.session.bytes(from: proxy.url("fixture", "/sse"))
            #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
            var data: [String] = []
            for try await line in bytes.lines where line.hasPrefix("data:") {
                data.append(line)
            }
            #expect(data == ["data: 1", "data: 2", "data: 3"])
        }
    }

    @Test func redirectsPassThroughUntouched() async throws {
        try await withProxy { proxy, _ in
            let (_, response) = try await proxy.send(URLRequest(url: proxy.url("fixture", "/redirect")), delegate: NoRedirects())
            #expect(response.statusCode == 302)
            #expect(response.value(forHTTPHeaderField: "Location") == "/echo?from=redirect")
        }
    }

    @Test func cookiesRoundTrip() async throws {
        try await withProxy { proxy, _ in
            let (_, set) = try await proxy.get("fixture", "/cookie/set")
            #expect(set.value(forHTTPHeaderField: "Set-Cookie")?.contains("flavor=oatmeal") == true)
            let (data, _) = try await proxy.get("fixture", "/cookie/get")
            #expect(try object(data)["cookie"] as? String == "flavor=oatmeal")
        }
    }

    @Test("HEAD keeps framing headers and sends no body", arguments: ["", "&chunked=1"])
    func head(_ variant: String) async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, """
                HEAD /download?bytes=1000\(variant) HTTP/1.1\r
                Host: fixture.localhost\r
                \r
                GET /echo HTTP/1.1\r
                Host: fixture.localhost\r
                Connection: close\r
                \r

                """)
            let responses = raw.components(separatedBy: "HTTP/1.1 200 OK")
            try #require(responses.count == 3, "expected HEAD then GET on one connection, got: \(raw)")
            let headPart = responses[1].lowercased()
            if variant.isEmpty {
                #expect(headPart.contains("content-length: 1000"))
            }
            #expect(!headPart.contains("xxxx"))
            #expect(!headPart.contains("\r\n0\r\n"))  // no stray chunk terminator
            #expect(responses[2].contains("\"method\":\"GET\""))
        }
    }

    @Test func expectContinueIsForwarded() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, """
                POST /continue HTTP/1.1\r
                Host: fixture.localhost\r
                Content-Length: 5\r
                Expect: 100-continue\r
                Connection: close\r
                \r
                hello
                """)
            #expect(raw.hasPrefix("HTTP/1.1 100 Continue\r\n"))
            #expect(raw.contains("HTTP/1.1 200 OK"))
            #expect(raw.contains("\"body\":\"hello\""))
        }
    }

    @Test func pipelinedRequestsAnswerInOrder() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, """
                GET /echo?n=1 HTTP/1.1\r
                Host: fixture.localhost\r
                \r
                GET /echo?n=2 HTTP/1.1\r
                Host: nothere.localhost\r
                \r
                GET /echo?n=3 HTTP/1.1\r
                Host: fixture.localhost\r
                Connection: close\r
                \r

                """)
            let first = try #require(raw.range(of: "/echo?n=1"))
            let second = try #require(raw.range(of: "No app is registered as nothere.localhost"))
            let third = try #require(raw.range(of: "/echo?n=3"))
            #expect(first.lowerBound < second.lowerBound && second.lowerBound < third.lowerBound)
        }
    }

    @Test func http10ClientsGetCloseDelimitedResponses() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, "GET /download?bytes=10&chunked=1 HTTP/1.0\r\nHost: fixture.localhost\r\n\r\n")
            #expect(raw.hasPrefix("HTTP/1.0 200 OK"))
            #expect(!raw.lowercased().contains("transfer-encoding"))
            #expect(raw.hasSuffix("\r\n\r\nxxxxxxxxxx"))
        }
    }

    @Test func absoluteFormTargetsRouteByAuthority() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, "GET http://fixture.localhost/echo?abs=1 HTTP/1.1\r\nHost: ignored.example\r\nConnection: close\r\n\r\n")
            #expect(raw.contains("HTTP/1.1 200 OK"))
            #expect(raw.contains(#""uri":"\/echo?abs=1""#))
            #expect(raw.contains(#"["host","fixture.localhost"]"#))
        }
    }

    // MARK: - Failures and routing

    @Test func backendDownIs502WithTheTarget() async throws {
        try await withProxy { proxy, _ in
            let closedPort = try ProxyHarness.freePort()
            try await proxy.register("down", "http://127.0.0.1:\(closedPort)")

            let (text, response) = try await proxy.get("down", "/")
            #expect(response.statusCode == 502)
            let body = String(decoding: text, as: UTF8.self)
            #expect(body.contains("down.localhost is registered, but its backend is unavailable."))
            #expect(body.contains("Target: 127.0.0.1:\(closedPort)"))

            let (json, _) = try await proxy.get("down", "/", headers: ["Accept": "application/json"])
            let error = try #require(try object(json)["error"] as? [String: String])
            #expect(error["code"] == "backend_unavailable")

            let (html, htmlResponse) = try await proxy.get("down", "/", headers: ["Accept": "text/html"])
            #expect(htmlResponse.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
            #expect(String(decoding: html, as: UTF8.self).contains("<dd class=\"mono\">127.0.0.1:\(closedPort)</dd>"))

            // The mapping survives its backend being down.
            #expect(proxy.registry.routes.target(for: "down") != nil)
        }
    }

    @Test func unknownNameIs404() async throws {
        try await withProxy { proxy, _ in
            let (data, response) = try await proxy.get("ghost", "/anything")
            #expect(response.statusCode == 404)
            #expect(String(decoding: data, as: UTF8.self).contains("No app is registered as ghost.localhost."))
        }
    }

    @Test func controlAPIIsOnlyOnSubpanelHost() async throws {
        try await withProxy { proxy, fixture in
            // On an app host, /api/v1/... belongs to the app.
            let (_, response) = try await proxy.get("fixture", "/api/v1/apps")
            #expect(response.statusCode == 404)
            #expect(response.value(forHTTPHeaderField: "X-Fixture") == fixture.id)

            // Bare localhost and IPs are not Subpanel.
            let (_, bare) = try await proxy.send(URLRequest(url: URL(string: "http://localhost:\(proxy.port)/api/v1/apps")!))
            #expect(bare.statusCode == 404)
        }
    }

    @Test func registrationUpdatesAndDeletesTakeEffectImmediately() async throws {
        try await withProxy { proxy, first in
            let second = try await BackendFixture.start(id: "second")
            defer { Task { await second.stop() } }

            func put(_ port: Int) async throws -> Int {
                var request = URLRequest(url: proxy.url("subpanel", "/api/v1/apps/live"))
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(#"{"target":"http://127.0.0.1:\#(port)"}"#.utf8)
                return try await proxy.send(request).1.statusCode
            }

            #expect(try await put(first.port) == 201)
            #expect(try await proxy.get("live", "/echo").1.value(forHTTPHeaderField: "X-Fixture") == "fixture")

            #expect(try await put(second.port) == 200)
            #expect(try await proxy.get("live", "/echo").1.value(forHTTPHeaderField: "X-Fixture") == "second")

            var delete = URLRequest(url: proxy.url("subpanel", "/api/v1/apps/live"))
            delete.httpMethod = "DELETE"
            #expect(try await proxy.send(delete).1.statusCode == 204)
            #expect(try await proxy.get("live", "/echo").1.statusCode == 404)
        }
    }

    @Test func instructionsOverTheWire() async throws {
        try await withProxy { proxy, _ in
            let (data, response) = try await proxy.get("subpanel", "/instructions")
            #expect(response.statusCode == 200)
            #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/markdown; charset=utf-8")
            #expect(String(decoding: data, as: UTF8.self).contains("http://subpanel.localhost:\(proxy.port)/api/v1/apps/myapp"))

            let (apps, _) = try await proxy.get("subpanel", "/api/v1/apps")
            let list = try APICoding.decoder.decode(AppListDTO.self, from: apps)
            #expect(list.apps.first?.reachable == true)
        }
    }

    @Test func localhostTargetsReachIPv6OnlyBackends() async throws {
        let proxy = try await ProxyHarness.start()
        let v6 = try await BackendFixture.start(host: "::1", id: "v6")
        try await proxy.register("dual", "http://localhost:\(v6.port)")
        try await proxy.register("v4only", "http://127.0.0.1:\(v6.port)")
        let (_, dual) = try await proxy.get("dual", "/echo")
        #expect(dual.statusCode == 200)
        #expect(dual.value(forHTTPHeaderField: "X-Fixture") == "v6")
        #expect(try await proxy.get("v4only", "/echo").1.statusCode == 502)
        await v6.stop()
        await proxy.stop()
    }

    @Test func forwardingLoopsAreCut() async throws {
        let proxy = try await ProxyHarness.start()
        try await proxy.register("loop", "http://127.0.0.1:\(proxy.port)")
        let (data, response) = try await proxy.get("loop", "/")
        #expect(response.statusCode == 508)
        #expect(String(decoding: data, as: UTF8.self).contains("looping back through Subpanel"))
        await proxy.stop()
    }

    // MARK: - WebSockets

    @Test func webSocketTunnel() async throws {
        try await withProxy { proxy, _ in
            let task = proxy.session.webSocketTask(with: URL(string: "ws://fixture.localhost:\(proxy.port)/ws")!)
            task.resume()

            // Sent by the backend right after its 101.
            guard case .string(let hello) = try await task.receive() else { Issue.record("expected text"); return }
            #expect(hello == "hello")

            try await task.send(.string("ping"))
            guard case .string(let echoed) = try await task.receive() else { Issue.record("expected text"); return }
            #expect(echoed == "ping")

            let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
            try await task.send(.data(payload))
            guard case .data(let binary) = try await task.receive() else { Issue.record("expected binary"); return }
            #expect(binary == payload)

            // Close initiated by the backend reaches the client.
            try await task.send(.string("close-me"))
            await #expect(throws: (any Error).self) { _ = try await task.receive() }
            #expect(task.closeCode == .normalClosure)
        }
    }

    @Test func webSocketToUnknownNameIs404AndCloses() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, """
                GET /ws HTTP/1.1\r
                Host: ghost.localhost\r
                Connection: Upgrade\r
                Upgrade: websocket\r
                Sec-WebSocket-Version: 13\r
                Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
                \r

                """)
            #expect(raw.hasPrefix("HTTP/1.1 404 Not Found"))
            #expect(raw.lowercased().contains("connection: close"))
        }
    }
}
