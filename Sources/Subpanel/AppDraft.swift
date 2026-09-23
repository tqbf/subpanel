import Foundation
import SubpanelCore

/// The editable form of a mapping, for the add/edit sheet.
struct AppDraft: Identifiable {
    let id = UUID()
    var name: String
    var host: LoopbackHost
    /// Text, not `Int?`: a numeric `TextField` only commits on Return/blur,
    /// so a click on "Save" could otherwise save the previous port.
    var portText: String
    /// Editing keeps the name fixed: renaming is delete + add.
    let isNew: Bool

    var port: Int? {
        Int(portText.trimmingCharacters(in: .whitespaces))
    }

    static func new() -> AppDraft {
        AppDraft(name: "", host: .ipv4, portText: "", isNew: true)
    }

    static func editing(_ app: AppDTO) -> AppDraft {
        let target = try? BackendTarget(parsing: app.target)
        return AppDraft(
            name: app.name,
            host: target.flatMap { LoopbackHost(rawValue: $0.host) } ?? .ipv4,
            portText: target.map { String($0.port) } ?? "",
            isNew: false
        )
    }

    var canSave: Bool {
        !name.isEmpty && port != nil
    }

    /// Validates with the same rules the service applies, so most mistakes
    /// are caught before a round trip. Returns the target URL string.
    func validatedTarget() throws -> String {
        _ = try AppName(validating: name)
        guard let port else {
            throw SubpanelError(.invalidTarget, "Enter the port your app is listening on.")
        }
        return try BackendTarget(host: host.rawValue, port: port).urlString
    }
}
