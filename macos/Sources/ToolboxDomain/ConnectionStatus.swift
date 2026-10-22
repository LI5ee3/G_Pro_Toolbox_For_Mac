package enum ConnectionStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(String)
    case scanning
    case awaitingAuthorization
    case offline(String)
    case failed(String)
}

package enum ManualConnectionMode: String, CaseIterable, Sendable {
    case tcp = "手动 TCP"
    case usb = "手动 USB"
}

package enum DeviceDiscoveryStatus: Equatable, Sendable {
    case idle, discovering
    case failed(AdbDiscoveryFailure)
}
