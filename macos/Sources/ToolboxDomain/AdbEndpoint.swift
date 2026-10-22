/// Immutable command destination, separate from a preset's persisted ownership key.
/// S1-04 exposes only TCP. Legacy host spelling is preserved; input parsing and discovery
/// stay at their existing boundaries, and no connection preference is persisted here.
package struct AdbEndpoint: Equatable, Sendable {
    private enum Transport: Equatable, Sendable {
        case tcp(host: String, port: UInt16)
    }
    private let transport: Transport

    package static func tcp(host: String, port: UInt16 = 5555) -> AdbEndpoint? {
        guard !host.isEmpty, port > 0 else { return nil }
        return AdbEndpoint(transport: .tcp(host: host, port: port))
    }

    /// Compatibility projection for the existing TCP UI and legacy preset identity.
    package var tcpHost: String {
        switch transport { case .tcp(let host, _): return host }
    }

    package var serial: String {
        switch transport { case .tcp(let host, let port): return "\(host):\(port)" }
    }
}
