import Foundation
import Observation
import SubpanelCore

/// The menu's state: the registered apps, each with whether a process is
/// listening on its target, as last polled from the service's API. The
/// service answers "listening" from the OS socket table, so nothing ever
/// connects to a backend to find out (plans/api.md).
@Observable
@MainActor
final class MenuModel {
    enum Health: Equatable {
        case checking
        case running
        case notResponding
    }

    private(set) var apps: [AppDTO] = []
    private(set) var health = Health.checking

    private let client = SubpanelClient.standard()
    private var pollTask: Task<Void, Never>?

    /// Starts background polling. Idempotent. The menu only ever shows the
    /// last poll, so opening it never waits on anything.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.poll() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func poll() async -> Duration {
        do {
            apps = try await client.apps()
            health = .running
        } catch {
            apps = []
            health = .notResponding
        }
        return health == .running ? .seconds(4) : .seconds(2)
    }
}
