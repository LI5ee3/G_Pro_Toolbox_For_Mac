import ToolboxDomain
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
    package var isConnected: Bool {
        if case .connected = connectionStatus { return true }
        return false
    }

    package var statusText: String {
        switch connectionStatus {
        case .disconnected: return "未连接"
        case .connecting: return "连接中"
        case .connected(let detail): return "已连接 (\(detail))"
        case .scanning: return "正在扫描内网..."
        }
    }

}
