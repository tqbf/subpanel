import Foundation
import NIOCore
import NIOPosix
import SubpanelCore

/// Answers "is anything listening at this target?" with a TCP connect,
/// cached briefly so listing apps stays cheap. Advisory only: routing never
/// waits on or consults it.
public actor TCPReachabilityProber: ReachabilityProbing {
    private struct Entry {
        var checkedAt: ContinuousClock.Instant
        var reachable: Bool
    }

    private let group: any EventLoopGroup
    private let ttl: Duration
    private let timeout: TimeAmount
    private var cache: [BackendTarget: Entry] = [:]
    private var inFlight: [BackendTarget: Task<Bool, Never>] = [:]

    public init(
        group: any EventLoopGroup = MultiThreadedEventLoopGroup.singleton,
        ttl: Duration = .seconds(2),
        timeout: TimeAmount = .milliseconds(750)
    ) {
        self.group = group
        self.ttl = ttl
        self.timeout = timeout
    }

    public func isReachable(_ target: BackendTarget) async -> Bool {
        let now = ContinuousClock.now
        if let entry = cache[target], now - entry.checkedAt < ttl {
            return entry.reachable
        }
        if let task = inFlight[target] {
            return await task.value
        }
        let task = Task { [group, timeout] in
            await Self.probe(target, group: group, timeout: timeout)
        }
        inFlight[target] = task
        let reachable = await task.value
        inFlight[target] = nil
        cache[target] = Entry(checkedAt: .now, reachable: reachable)
        return reachable
    }

    private static func probe(_ target: BackendTarget, group: any EventLoopGroup, timeout: TimeAmount) async -> Bool {
        do {
            let channel = try await ClientBootstrap(group: group)
                .connectTimeout(timeout)
                .connect(host: target.host, port: target.port)
                .get()
            try? await channel.close()
            return true
        } catch {
            return false
        }
    }
}
