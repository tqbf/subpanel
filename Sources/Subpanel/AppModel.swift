import Foundation
import Observation
import SubpanelCore

/// App-wide state: the service's health and mappings as last polled, plus
/// every action the UI can take. Owned by `SubpanelApp` with `@State`,
/// passed down with `@Environment`.
///
/// The service is the authority (plans/architecture.md). This model only
/// mirrors it — by polling the HTTP API in the background, so opening the
/// menu never waits on the network.
@Observable
@MainActor
final class AppModel {
    private(set) var apps: [AppDTO] = []
    private(set) var status: StatusDTO?
    private(set) var health = ServiceHealth.checking
    private(set) var registration: ServiceManager.Registration
    /// A service install/restart is in flight.
    private(set) var isChangingService = false
    /// The last failed user action, for whichever window is showing to alert.
    var actionError: String?

    let client: SubpanelClient
    private let service: ServiceManager
    private var pollTask: Task<Void, Never>?
    /// Bumped per refresh so a slow, older response can't overwrite a newer one.
    private var refreshGeneration = 0

    init(client: SubpanelClient = .standard(), service: ServiceManager = ServiceManager()) {
        self.client = client
        self.service = service
        self.registration = service.registration
    }

    var instructionsURL: URL { client.instructionsURL }

    var isRunning: Bool { health == .running }

    /// Drives the "Something Went Wrong" alert in whichever window is open.
    /// Dismissing it clears the error.
    var isShowingActionError: Bool {
        get { actionError != nil }
        set { if !newValue { actionError = nil } }
    }

    // MARK: - Polling

    /// Starts background polling. Idempotent.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.poll() else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// One poll; returns how long to wait before the next. Polls faster while
    /// the service is down so recovery shows quickly.
    private func poll() async -> Duration {
        await refresh()
        return isRunning ? .seconds(5) : .seconds(2)
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        registration = service.registration
        do {
            async let status = client.status()
            async let apps = client.apps()
            let (newStatus, newApps) = try await (status, apps)
            guard generation == refreshGeneration else { return }
            self.status = newStatus
            self.apps = newApps
            health = .running
        } catch {
            guard generation == refreshGeneration else { return }
            health = .notResponding
            status = nil
            apps = []
        }
    }

    // MARK: - Mappings

    /// Creates or updates a mapping. Throws the API's error (e.g. an invalid
    /// name) so the editor can show it inline.
    func save(name: String, target: String) async throws {
        _ = try await client.put(name: name, target: target)
        await refresh()
    }

    func delete(_ names: some Sequence<String>) async {
        for name in names {
            do {
                try await client.delete(name: name)
            } catch {
                actionError = error.localizedDescription
            }
        }
        await refresh()
    }

    func app(named name: String) -> AppDTO? {
        apps.first { $0.name == name }
    }

    // MARK: - Service lifecycle

    /// First run: put the menu-bar item in place if it never has been.
    func installMenuBarItemIfNeeded() {
        guard !MenuBarItem.isRegistered else { return }
        do {
            try MenuBarItem.set(true)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// First run: register the agent if it never has been.
    func installServiceIfNeeded() async {
        registration = service.registration
        guard registration == .notRegistered else { return }
        await changeService { try service.install() }
    }

    func repairService() async {
        await changeService { try await service.reinstall() }
    }

    func restartService() async {
        await changeService { try await service.restart() }
    }

    private func changeService(_ change: () async throws -> Void) async {
        guard !isChangingService else { return }
        isChangingService = true
        defer { isChangingService = false }
        do {
            try await change()
        } catch {
            actionError = error.localizedDescription
        }
        // Give launchd a moment to (re)start the job, then report what we see.
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
            if isRunning { return }
        }
    }
}
