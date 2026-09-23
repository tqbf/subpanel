import Foundation

/// A validated app name — a single DNS label that becomes `<name>.localhost`.
///
/// Rules (plans/registry.md): ASCII lowercase letters, digits and `-`; starts
/// and ends with a letter or digit; at most 63 characters; not reserved.
/// Uppercase is *rejected* with a hint rather than silently lowercased, so a
/// caller never ends up with a mapping under a name it didn't ask for.
public struct AppName: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public static let maxLength = 63

    public init(validating raw: String) throws(SubpanelError) {
        try Self.validate(raw)
        rawValue = raw
    }

    public var description: String { rawValue }

    public static func < (lhs: AppName, rhs: AppName) -> Bool { lhs.rawValue < rhs.rawValue }

    private static func validate(_ raw: String) throws(SubpanelError) {
        guard !raw.isEmpty else {
            throw SubpanelError(.invalidName, "App name is empty. Use a lowercase label such as 'myapp'.")
        }
        if raw.hasSuffix(".\(SubpanelConstants.domain)") || raw.contains(".") {
            let label = raw.split(separator: ".").first.map(String.init) ?? raw
            throw SubpanelError(
                .invalidName,
                "Pass only the label, not a hostname: use '\(label)', not '\(raw)'."
            )
        }
        guard raw.utf8.count <= maxLength else {
            throw SubpanelError(.invalidName, "App names may be at most \(maxLength) characters.")
        }
        let lowered = raw.lowercased()
        if lowered != raw, isWellFormedLabel(lowered) {
            throw SubpanelError(.invalidName, "App names must be lowercase: use '\(lowered)'.")
        }
        guard raw.utf8.allSatisfy(isLabelByte) else {
            throw SubpanelError(
                .invalidName,
                "App names may contain only lowercase letters, digits, and hyphens."
            )
        }
        guard isWellFormedLabel(raw) else {
            throw SubpanelError(.invalidName, "App names must start and end with a letter or digit.")
        }
        if SubpanelConstants.reservedNames.contains(raw) {
            throw SubpanelError(.reservedName, "'\(raw)' is reserved for Subpanel itself. Pick another name.")
        }
    }

    private static func isWellFormedLabel(_ label: String) -> Bool {
        let bytes = Array(label.utf8)
        guard let first = bytes.first, let last = bytes.last else { return false }
        return bytes.allSatisfy(isLabelByte) && first != UInt8(ascii: "-") && last != UInt8(ascii: "-")
    }

    private static func isLabelByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"):
            true
        default:
            false
        }
    }
}
