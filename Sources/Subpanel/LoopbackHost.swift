/// The three backend hosts Subpanel accepts.
enum LoopbackHost: String, CaseIterable, Identifiable {
    case ipv4 = "127.0.0.1"
    case ipv6 = "::1"
    case localhost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ipv4: "127.0.0.1 (IPv4)"
        case .ipv6: "::1 (IPv6)"
        case .localhost: "localhost (either)"
        }
    }
}
