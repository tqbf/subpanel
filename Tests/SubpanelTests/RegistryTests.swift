import Foundation
import Testing
@testable import SubpanelCore

/// A scratch directory per test, removed afterwards.
struct TempDir: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "subpanel-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var registry: URL { url.appending(path: "registry.json") }

    func contents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("Persistence")
struct RegistryStoreTests {
    @Test func missingFileIsEmpty() throws {
        let dir = try TempDir()
        let result = RegistryStore(url: dir.registry).load()
        #expect(result.mappings.isEmpty)
        #expect(result.warning == nil)
    }

    @Test func roundTrip() throws {
        let dir = try TempDir()
        let store = RegistryStore(url: dir.registry)
        let mapping = AppMapping(
            name: try AppName(validating: "wiki"),
            target: try BackendTarget(parsing: "http://127.0.0.1:43127"),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        try store.save([mapping])
        let loaded = store.load()
        #expect(loaded.warning == nil)
        #expect(loaded.mappings == [mapping])

        let json = try String(contentsOf: dir.registry, encoding: .utf8)
        #expect(json.contains(#""version" : 1"#))
        #expect(json.contains(#""targetPort" : 43127"#))
    }

    @Test func saveReplacesAtomicallyAndLeavesNoTempFiles() throws {
        let dir = try TempDir()
        let store = RegistryStore(url: dir.registry)
        let name = try AppName(validating: "a")
        for port in [3001, 3002, 3003] {
            try store.save([AppMapping(name: name, target: try BackendTarget(host: "127.0.0.1", port: port), createdAt: .now, updatedAt: .now)])
        }
        #expect(store.load().mappings.map(\.targetPort) == [3003])
        #expect(try dir.contents() == ["registry.json"])
    }

    @Test func malformedFileIsPreservedNotOverwritten() throws {
        let dir = try TempDir()
        try Data("{ this is not json".utf8).write(to: dir.registry)
        let result = RegistryStore(url: dir.registry).load()
        #expect(result.mappings.isEmpty)
        let warning = try #require(result.warning)
        #expect(warning.contains("not valid registry JSON"))

        let files = try dir.contents()
        #expect(files.count == 1)
        let aside = try #require(files.first)
        #expect(aside.hasPrefix("registry.json.unreadable-"))
        #expect(try String(contentsOf: dir.url.appending(path: aside), encoding: .utf8) == "{ this is not json")
    }

    @Test func unknownSchemaVersionIsSetAside() throws {
        let dir = try TempDir()
        try Data(#"{"version": 2, "apps": [], "somethingNew": true}"#.utf8).write(to: dir.registry)
        let result = RegistryStore(url: dir.registry).load()
        #expect(result.warning?.contains("schema version 2") == true)
        #expect(try dir.contents().first?.hasPrefix("registry.json.unreadable-") == true)
    }

    @Test func invalidEntryIsSetAside() throws {
        let dir = try TempDir()
        let json = #"""
        {"version": 1, "apps": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "name": "Bad_Name",
          "targetHost": "127.0.0.1", "targetPort": 3000,
          "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}]}
        """#
        try Data(json.utf8).write(to: dir.registry)
        let result = RegistryStore(url: dir.registry).load()
        #expect(result.mappings.isEmpty)
        #expect(result.warning?.contains("Bad_Name") == true)
    }
}

@Suite("Registry")
struct MappingRegistryTests {
    let wiki = try! AppName(validating: "wiki")
    let first = try! BackendTarget(parsing: "http://127.0.0.1:43127")
    let second = try! BackendTarget(parsing: "http://[::1]:49281")

    @Test func putCreatesUpdatesAndIsIdempotent() async throws {
        let registry = MappingRegistry(store: nil)
        let created = try await registry.put(wiki, target: first)
        guard case .created(let mapping) = created else { Issue.record("expected created"); return }
        #expect(mapping.name == "wiki")

        #expect(try await registry.put(wiki, target: first) == .unchanged(mapping))

        let updated = try await registry.put(wiki, target: second)
        guard case .updated(let next) = updated else { Issue.record("expected updated"); return }
        #expect(next.id == mapping.id)
        #expect(next.createdAt == mapping.createdAt)
        #expect(next.target == second)
        #expect(await registry.count == 1)
    }

    @Test func routingSnapshotFollowsEveryMutation() async throws {
        let registry = MappingRegistry(store: nil)
        #expect(registry.routes.target(for: "wiki") == nil)
        try await registry.put(wiki, target: first)
        #expect(registry.routes.target(for: "wiki") == first)
        try await registry.put(wiki, target: second)
        #expect(registry.routes.target(for: "wiki") == second)
        try await registry.remove(wiki)
        #expect(registry.routes.target(for: "wiki") == nil)
    }

    @Test func removeIsIdempotent() async throws {
        let registry = MappingRegistry(store: nil)
        try await registry.put(wiki, target: first)
        #expect(try await registry.remove(wiki))
        #expect(try await !registry.remove(wiki))
    }

    @Test func persistsAndReloads() async throws {
        let dir = try TempDir()
        let registry = MappingRegistry(store: RegistryStore(url: dir.registry))
        await registry.load()
        try await registry.put(wiki, target: first)
        try await registry.put(try AppName(validating: "phone"), target: second)
        #expect(await registry.lastWrite != nil)

        let reloaded = MappingRegistry(store: RegistryStore(url: dir.registry))
        await reloaded.load()
        #expect(await reloaded.all().map(\.name) == ["phone", "wiki"])
        #expect(reloaded.routes.target(for: "phone") == second)
    }

    @Test func failedSaveLeavesMemoryUnchanged() async throws {
        let dir = try TempDir()
        // A directory where the registry file should be makes every write fail.
        try FileManager.default.createDirectory(at: dir.registry.appending(path: "blocker"), withIntermediateDirectories: true)
        let registry = MappingRegistry(store: RegistryStore(url: dir.registry))
        await #expect(throws: (any Error).self) { try await registry.put(wiki, target: first) }
        #expect(await registry.count == 0)
        #expect(registry.routes.target(for: "wiki") == nil)
    }
}
