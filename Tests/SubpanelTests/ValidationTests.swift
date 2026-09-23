import Testing
@testable import SubpanelCore

@Suite("Name validation")
struct AppNameTests {
    @Test("accepts plain labels", arguments: ["foo", "foo-bar", "foo2", "wiki", "my-app", "phone2", "foo-bar-7", "a", "0x", String(repeating: "a", count: 63)])
    func valid(_ name: String) throws {
        #expect(try AppName(validating: name).rawValue == name)
    }

    @Test("rejects malformed labels", arguments: ["", "foo_bar", "foo.localhost", "foo.bar", "-local", "local-", "foo/bar", "foo bar", "héllo", String(repeating: "a", count: 64)])
    func invalid(_ name: String) {
        #expect(throws: SubpanelError.self) { try AppName(validating: name) }
        #expect(code(name) == .invalidName)
    }

    @Test func uppercaseIsRejectedWithAHint() {
        let error = capture { try AppName(validating: "Foo") }
        #expect(error?.code == .invalidName)
        #expect(error?.message.contains("'foo'") == true)
    }

    @Test func hostnameInputSuggestsTheLabel() {
        let error = capture { try AppName(validating: "foo.localhost") }
        #expect(error?.message.contains("use 'foo'") == true)
    }

    @Test func subpanelIsReserved() {
        #expect(code("subpanel") == .reservedName)
        #expect(SubpanelErrorCode.reservedName.httpStatus == 409)
    }

    private func code(_ name: String) -> SubpanelErrorCode? {
        capture { try AppName(validating: name) }?.code
    }
}

@Suite("Target validation")
struct BackendTargetTests {
    @Test("accepts loopback HTTP", arguments: [
        ("http://127.0.0.1:3000", "127.0.0.1", 3000, "http://127.0.0.1:3000"),
        ("http://127.0.0.1:43127/", "127.0.0.1", 43127, "http://127.0.0.1:43127"),
        ("http://[::1]:5173", "::1", 5173, "http://[::1]:5173"),
        ("http://localhost:8080", "localhost", 8080, "http://localhost:8080"),
        ("HTTP://LOCALHOST:8080", "localhost", 8080, "http://localhost:8080"),
    ])
    func valid(_ input: String, host: String, port: Int, canonical: String) throws {
        let target = try BackendTarget(parsing: input)
        #expect(target.host == host)
        #expect(target.port == port)
        #expect(target.urlString == canonical)
    }

    @Test("rejects everything else", arguments: [
        ("https://127.0.0.1:3000", SubpanelErrorCode.invalidTarget),
        ("http://192.168.1.10:3000", .nonLoopbackTarget),
        ("http://example.com", .invalidTarget),
        ("http://example.com:80", .nonLoopbackTarget),
        ("http://127.0.0.2:3000", .nonLoopbackTarget),
        ("file:///tmp/foo", .invalidTarget),
        ("http://127.0.0.1", .invalidTarget),
        ("http://127.0.0.1:80", .invalidTarget),
        ("http://127.0.0.1:3000/app", .invalidTarget),
        ("http://127.0.0.1:3000?x=1", .invalidTarget),
        ("http://user:pw@127.0.0.1:3000", .invalidTarget),
        ("127.0.0.1:3000", .invalidTarget),
        ("", .invalidTarget),
    ])
    func invalid(_ input: String, expected: SubpanelErrorCode) {
        #expect(capture { try BackendTarget(parsing: input) }?.code == expected)
    }

    @Test func authorityBracketsIPv6() throws {
        #expect(try BackendTarget(host: "::1", port: 9).authority == "[::1]:9")
        #expect(try BackendTarget(host: "127.0.0.1", port: 9).authority == "127.0.0.1:9")
    }
}

@Suite("Host routing")
struct HostRouteTests {
    @Test("routes by Host header", arguments: [
        ("subpanel.localhost", HostRoute.control),
        ("SUBPANEL.LOCALHOST:80", .control),
        ("subpanel.localhost.", .control),
        ("wiki.localhost", .app("wiki")),
        ("Wiki.Localhost:8080", .app("wiki")),
        ("wiki.localhost.:80", .app("wiki")),
    ])
    func routes(_ host: String, expected: HostRoute) {
        #expect(HostRoute(hostHeader: host) == expected)
    }

    @Test("rejects other hosts", arguments: ["localhost", "127.0.0.1", "[::1]:80", "example.com", "a.b.localhost", ".localhost", "wiki.localhost.com"])
    func invalid(_ host: String) {
        #expect(HostRoute(hostHeader: host) == .invalid(host))
    }

    @Test func missingHost() {
        #expect(HostRoute(hostHeader: nil) == .invalid(nil))
        #expect(HostRoute(hostHeader: "  ") == .invalid(nil))
    }
}

func capture(_ body: () throws -> some Any) -> SubpanelError? {
    do {
        _ = try body()
        return nil
    } catch {
        return error as? SubpanelError
    }
}
