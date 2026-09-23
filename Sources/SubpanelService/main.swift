import Dispatch
import Foundation
import os
import SubpanelCore
import SubpanelServer

// subpanel-service — the process that owns port 80 (plans/service-lifecycle.md).
//
// In production launchd starts it from Subpanel.app's LaunchAgent and passes
// it the 127.0.0.1:80 / [::1]:80 listening sockets. For development, pass
// --port to bind an unprivileged port yourself.

let usage = """
    usage: subpanel-service [--port N] [--registry PATH] [--verbose]

      (no --port)      use the sockets launchd activated for this job (port 80)
      --port N         bind 127.0.0.1:N and [::1]:N instead (development)
      --registry PATH  registry file (default: ~/Library/Application Support/Subpanel/registry.json)
      --verbose        log a summary line per request (debug level)
    """

struct Options {
    var port: Int?
    var registry = SubpanelConstants.defaultRegistryURL
    var verbose = false
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = arguments.next() {
        switch argument {
        case "--port":
            guard let value = arguments.next(), let port = Int(value), (1...65_535).contains(port) else {
                fail("--port needs a port number")
            }
            options.port = port
        case "--registry":
            guard let value = arguments.next() else { fail("--registry needs a path") }
            options.registry = URL(filePath: (value as NSString).expandingTildeInPath)
        case "--verbose":
            options.verbose = true
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unknown argument '\(argument)'")
        }
    }
    return options
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("subpanel-service: \(message)\n\n\(usage)\n".utf8))
    exit(code)
}

/// launchd starts agents with a soft limit of 256 descriptors, and every
/// proxied request holds two (client + backend). Raise the soft limit as far
/// as the system allows.
func raiseDescriptorLimit() -> rlim_t {
    var limit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return 0 }
    for wanted: rlim_t in [65_536, 10_240] where limit.rlim_cur < wanted {
        var raised = limit
        raised.rlim_cur = min(wanted, limit.rlim_max)
        if setrlimit(RLIMIT_NOFILE, &raised) == 0 {
            return raised.rlim_cur
        }
    }
    return limit.rlim_cur
}

let log = Logger(subsystem: SubpanelConstants.logSubsystem, category: "service")
let options = parseOptions()
let descriptorLimit = raiseDescriptorLimit()
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

// 1. State first: the registry is loaded before any traffic is accepted.
let registry = MappingRegistry(store: RegistryStore(url: options.registry))
await registry.load()

// 2. Listeners.
let listeners: [ProxyServer.Listener]
let listenerNames: [String]
let publicPort: Int
if let port = options.port {
    listeners = [.bind(host: "127.0.0.1", port: port), .bind(host: "::1", port: port)]
    listenerNames = listeners.map(\.description)
    publicPort = port
} else {
    do {
        let fds = try SubpanelConstants.launchdSocketNames.flatMap(LaunchdSockets.activate)
        listeners = fds.map { .descriptor($0) }
        listenerNames = fds.map { LaunchdSockets.localAddress(of: $0) ?? "fd \($0)" }
        publicPort = SubpanelConstants.proxyPort
    } catch {
        log.error("socket activation failed: \(String(describing: error), privacy: .public)")
        // EX_CONFIG. Under launchd this means the plist is wrong; by hand it
        // means you wanted --port.
        fail("\(error). Run from launchd, or pass --port for development.", code: 78)
    }
}

// 3. Serve.
let info = ServiceInfo(
    version: version,
    pid: getpid(),
    startedAt: .now,
    listeners: listenerNames,
    publicPort: publicPort
)
var configuration = ProxyConfiguration(publicPort: publicPort)
configuration.logRequests = options.verbose
let server = ProxyServer(
    routes: registry.routes,
    control: ControlAPI(registry: registry, info: info, prober: TCPReachabilityProber()),
    configuration: configuration
)

do {
    try await server.start(listeners)
} catch {
    log.error("listener failed: \(String(describing: error), privacy: .public)")
    fail("could not listen: \(error)", code: 71)
}
log.notice("subpanel-service \(version, privacy: .public) (pid \(getpid())) serving \(listenerNames.joined(separator: ", "), privacy: .public); fd limit \(descriptorLimit)")
if options.port != nil {
    print("subpanel-service \(version) listening on \(listenerNames.joined(separator: ", "))")
    print("agent instructions: \(SubpanelConstants.controlBaseURL(port: publicPort))/instructions")
}

// launchd stops the job with SIGTERM; ^C in a terminal sends SIGINT.
var signalSources: [any DispatchSourceSignal] = []
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        log.notice("subpanel-service stopping (signal \(signalNumber))")
        Task {
            await server.shutdown()
            exit(0)
        }
    }
    source.resume()
    signalSources.append(source)
}

await server.waitUntilClosed()
