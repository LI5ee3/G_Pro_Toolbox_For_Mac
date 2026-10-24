import Foundation
import ToolboxDomain
import ToolboxApplication

/// Local sheet input. Editing or selecting a candidate never changes the running session.
@MainActor
struct ConnectionDraft {
    var mode: ManualConnectionMode
    var host: String
    var port: String
    var usbSerial: String

    init(connection: ConnectionModel) {
        mode = connection.mode
        host = connection.ipInput
        port = connection.tcpPortInput
        usbSerial = connection.selectedUSBSerial
    }

    func canConnect(_ connection: ConnectionModel) -> Bool {
        guard !connection.connectionInProgress else { return false }
        if mode == .tcp {
            return AdbEndpoint.inputTCP(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port) != nil
        }
        guard connection.discoveryStatus != .discovering else { return false }
        return connection.discoveredDevices.contains { $0.serial == usbSerial && $0.canValidateAsUSB }
    }

    func connect(using actions: AppCoordinator) {
        let connection = actions.connection
        guard canConnect(connection) else { return }
        if connection.mode != mode { actions.setConnectionMode(mode) }
        else if connection.connectionStatus != .disconnected { actions.disconnectAdb() }
        if mode == .usb { actions.connectUSB(serial: usbSerial) }
        else {
            connection.ipInput = host.trimmingCharacters(in: .whitespacesAndNewlines)
            connection.tcpPortInput = port
            actions.connect()
        }
    }

    func diagnose(using actions: AppCoordinator) {
        let connection = actions.connection
        let previousHost = connection.ipInput, previousPort = connection.tcpPortInput
        defer { connection.ipInput = previousHost; connection.tcpPortInput = previousPort }
        connection.ipInput = host; connection.tcpPortInput = port
        // The existing entry captures both inputs synchronously before scheduling its work.
        actions.runDiagnostics()
    }

    static func saveCurrentPreference(using actions: AppCoordinator) {
        let connection = actions.connection
        guard connection.isConnected, let endpoint = connection.activeEndpoint else { return }
        let previousHost = connection.ipInput, previousPort = connection.tcpPortInput
        let previousSelection = connection.selectedEndpoint
        defer {
            connection.ipInput = previousHost; connection.tcpPortInput = previousPort
            connection.selectedEndpoint = previousSelection
        }
        if endpoint.isUSB { connection.selectedEndpoint = endpoint }
        else {
            connection.ipInput = endpoint.tcpHost
            connection.tcpPortInput = String(endpoint.tcpPort ?? 5555)
        }
        actions.saveConnectionPreference()
    }
}
