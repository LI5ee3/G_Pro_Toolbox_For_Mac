package enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(String)
    case scanning
}
