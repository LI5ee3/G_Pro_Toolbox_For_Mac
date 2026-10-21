import Foundation
import Observation
import MimonitorPresetCore

@MainActor @Observable
package final class ConnectionModel {
    package var connectionStatus: ConnectionStatus = .disconnected
    package var scannedDevices: [String] = []
    package var scannedDeviceModels: [String: String] = [:]
    package var selectedDevice: String = ""
    package var ipInput: String = ""
    var intent = ConnectionIntent()
    package init() {}
}
