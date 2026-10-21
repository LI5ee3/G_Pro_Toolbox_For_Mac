package enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(String)
    case scanning
}

