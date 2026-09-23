/// Whether the proxy is answering at `subpanel.localhost`, as last polled.
enum ServiceHealth: Equatable {
    /// No answer yet (just launched).
    case checking
    case running
    case notResponding
}
