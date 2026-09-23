import Foundation

/// Reads and writes `registry.json`.
///
/// - Writes are atomic (temp file + rename, via `Data.WritingOptions.atomic`).
/// - A file that can't be decoded — malformed JSON, an unknown schema version,
///   an entry that no longer validates — is never silently overwritten: it is
///   renamed aside (`registry.json.unreadable-<timestamp>`) and the reason is
///   returned so the service can surface it (plans/registry.md).
public struct RegistryStore: Sendable {
    /// The on-disk schema version this build reads and writes.
    public static let schemaVersion = 1

    public let url: URL

    public init(url: URL = SubpanelConstants.defaultRegistryURL) {
        self.url = url
    }

    /// The result of loading: the mappings, plus a warning if the file on
    /// disk had to be set aside.
    public struct LoadResult: Sendable {
        public var mappings: [AppMapping]
        public var warning: String?
    }

    struct FileFormat: Codable {
        var version: Int
        var apps: [AppMapping]
    }

    struct VersionProbe: Decodable {
        var version: Int?
    }

    public func load() -> LoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return LoadResult(mappings: [], warning: nil)
        } catch {
            return quarantine(reason: "could not be read (\(error.localizedDescription))")
        }

        let decoder = Self.decoder
        let version = (try? decoder.decode(VersionProbe.self, from: data))?.version
        if let version, version != Self.schemaVersion {
            return quarantine(reason: "has schema version \(version); this build understands version \(Self.schemaVersion)")
        }
        let file: FileFormat
        do {
            file = try decoder.decode(FileFormat.self, from: data)
        } catch {
            return quarantine(reason: "is not valid registry JSON (\(Self.describe(error)))")
        }

        var seen = Set<String>()
        for mapping in file.apps {
            do {
                _ = try mapping.validated()
            } catch {
                return quarantine(reason: "contains an invalid mapping '\(mapping.name)' (\(error.message))")
            }
            guard seen.insert(mapping.name).inserted else {
                return quarantine(reason: "contains '\(mapping.name)' more than once")
            }
        }
        return LoadResult(mappings: file.apps, warning: nil)
    }

    /// Atomically replaces the registry file with `mappings`.
    public func save(_ mappings: [AppMapping]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = FileFormat(version: Self.schemaVersion, apps: mappings.sorted { $0.name < $1.name })
        let data = try Self.encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    /// Moves the unreadable file aside so it's preserved, never overwritten.
    private func quarantine(reason: String) -> LoadResult {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let aside = url.deletingLastPathComponent()
            .appending(path: "\(url.lastPathComponent).unreadable-\(stamp)")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return LoadResult(
                mappings: [],
                warning: "\(url.lastPathComponent) \(reason). It was preserved as \(aside.lastPathComponent) and Subpanel started with no mappings."
            )
        } catch {
            return LoadResult(
                mappings: [],
                warning: "\(url.lastPathComponent) \(reason), and moving it aside failed (\(error.localizedDescription)). Subpanel started with no mappings; fix or remove the file."
            )
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
             DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            context.debugDescription
        default:
            error.localizedDescription
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
