import Foundation
import Testing
@testable import SubpanelCore
@testable import SubpanelServer

/// One test per defect found in the adversarial review of the proxy
/// (PROGRESS.md, 2026-09-23). An extension of the serialized "Proxy" suite,
/// so nothing else creates exchanges concurrently (the leak test counts them).
extension ProxyIntegrationTests {
    // MARK: High

    @Test func invalidStatusBelow100Is502AndTheServiceSurvives() async throws {
        try await withProxy { proxy, _ in
            let bad = try await ScriptedBackend.start(response: "HTTP/1.1 000 X\r\n\r\n", closeAfter: true)
            try await proxy.register("bad", "http://127.0.0.1:\(bad.port)")
            let raw = try await RawClient.exchange(port: proxy.port, "GET / HTTP/1.1\r\nHost: bad.localhost\r\nConnection: close\r\n\r\n")
            #expect(raw.hasPrefix("HTTP/1.1 502 Bad Gateway"))
            // Still alive (this used to crash the process).
            #expect(try await proxy.get("fixture", "/echo").1.statusCode == 200)
            await bad.stop()
        }
    }

    #if DEBUG
    @Test func finishedExchangesAreFreed() async throws {
        try await withProxy { proxy, _ in
            for _ in 0..<40 {
                _ = try await proxy.get("fixture", "/echo")
            }
            try await Task.sleep(for: .milliseconds(200))
            // Keep-alive connections are idle now; no exchange may outlive its
            // response (a BackendHandler ↔ exchange cycle used to leak them all).
            #expect(ProxyExchange.live.withLockedValue { $0 } == 0)
        }
    }
    #endif

    // MARK: Medium

    @Test func idleKeepAliveConnectionsAreClosed() async throws {
        let proxy = try await ProxyHarness.start { $0.idleTimeout = .milliseconds(300) }
        let start = ContinuousClock.now
        // Send nothing; the server should hang up well before our 5 s timeout.
        _ = try await RawClient.exchange(port: proxy.port, "", timeout: .seconds(5))
        #expect(ContinuousClock.now - start < .seconds(2))
        await proxy.stop()
    }

    @Test("half-closing clients still get the response", arguments: ["fixture", "subpanel"])
    func halfClosedClientsGetTheirResponse(_ host: String) async throws {
        try await withProxy { proxy, _ in
            let path = host == "subpanel" ? "/api/v1/status" : "/echo"
            let raw = try await RawClient.exchange(
                port: proxy.port,
                "GET \(path) HTTP/1.0\r\nHost: \(host).localhost\r\n\r\n",
                halfClose: true
            )
            #expect(raw.hasPrefix("HTTP/1.0 200 OK"))
        }
    }

    @Test func frameSentWith101BeforeHangingUpIsRelayed() async throws {
        try await withProxy { proxy, _ in
            let backend = try await ScriptedBackend.start(
                response: "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\nGOODBYE-FRAME",
                closeAfter: true
            )
            try await proxy.register("bye", "http://127.0.0.1:\(backend.port)")
            for _ in 0..<4 {
                let raw = try await RawClient.exchange(port: proxy.port, """
                    GET /ws HTTP/1.1\r
                    Host: bye.localhost\r
                    Connection: Upgrade\r
                    Upgrade: websocket\r
                    \r

                    """)
                #expect(raw.hasPrefix("HTTP/1.1 101 Switching Protocols"))
                #expect(raw.hasSuffix("GOODBYE-FRAME"))
            }
            await backend.stop()
        }
    }

    // MARK: Low

    @Test func absoluteFormControlRequest() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, "GET http://subpanel.localhost:\(proxy.port)/api/v1/status HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
            #expect(raw.hasPrefix("HTTP/1.1 200 OK"))
            #expect(raw.contains("\"apiVersion\""))
        }
    }

    @Test func pipelinedRequestAfterAClosingResponseDoesNotEatIt() async throws {
        try await withProxy { proxy, _ in
            // HTTP/1.0 keep-alive requests are answered and then closed; the
            // second request used to arrive re-entrantly and discard the first
            // (unflushed) response.
            let request = "GET /echo HTTP/1.0\r\nHost: fixture.localhost\r\nConnection: keep-alive\r\n\r\n"
            let raw = try await RawClient.exchange(port: proxy.port, request + request)
            #expect(raw.hasPrefix("HTTP/1.0 200 OK"))
            #expect(raw.contains("\"method\":\"GET\""))
        }
    }

    @Test func connectionHeaderCannotStripContentLength() async throws {
        try await withProxy { proxy, _ in
            let smuggled = "GET /echo?smuggled HTTP/1.1\r\nHost: evil\r\n\r\n"
            let raw = try await RawClient.exchange(port: proxy.port, """
                GET /echo HTTP/1.1\r
                Host: fixture.localhost\r
                Connection: close, Content-Length\r
                Content-Length: \(smuggled.utf8.count)\r
                \r
                \(smuggled)
                """)
            // One request, whose body is the would-be smuggled bytes.
            #expect(raw.components(separatedBy: "HTTP/1.1 200 OK").count == 2)
            #expect(raw.contains("\"bodyLength\":\(smuggled.utf8.count)"))
            #expect(!raw.contains("smuggled\",\"headers"))
        }
    }

    @Test func connectIsRefusedAndTheConnectionClosed() async throws {
        try await withProxy { proxy, _ in
            // NIO stops parsing after CONNECT, so keeping the connection would
            // hang whatever the client sends next.
            let start = ContinuousClock.now
            let raw = try await RawClient.exchange(port: proxy.port, "CONNECT fixture.localhost:80 HTTP/1.1\r\nHost: fixture.localhost\r\n\r\n")
            #expect(raw.hasPrefix("HTTP/1.1 405 Method Not Allowed"))
            #expect(raw.lowercased().contains("connection: close"))
            #expect(ContinuousClock.now - start < .seconds(2))  // closed, not hung
        }
    }

    @Test func traceIsRefused() async throws {
        try await withProxy { proxy, _ in
            let raw = try await RawClient.exchange(port: proxy.port, "TRACE / HTTP/1.1\r\nHost: fixture.localhost\r\nConnection: close\r\n\r\n")
            #expect(raw.hasPrefix("HTTP/1.1 405 Method Not Allowed"))
            #expect(!raw.contains("X-Fixture"))  // never reached the backend
        }
    }

    @Test("Expect: 100-continue is answered at once when Subpanel answers locally", arguments: ["subpanel", "ghost"])
    func expectContinueForLocalAnswers(_ host: String) async throws {
        try await withProxy { proxy, _ in
            // Send only the head, as a client waiting for 100 Continue does.
            let reads = try await RawClient.timeline(port: proxy.port, """
                PUT /api/v1/apps/x HTTP/1.1\r
                Host: \(host).localhost\r
                Content-Length: 40\r
                Expect: 100-continue\r
                \r

                """, timeout: .milliseconds(600))
            let text = reads.map(\.text).joined()
            if host == "subpanel" {
                #expect(text.hasPrefix("HTTP/1.1 100 Continue"))
            } else {
                #expect(text.hasPrefix("HTTP/1.1 404 Not Found"))
            }
        }
    }
}
