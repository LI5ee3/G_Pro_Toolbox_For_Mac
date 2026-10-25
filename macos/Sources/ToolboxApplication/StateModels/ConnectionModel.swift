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
    package var tcpPortInput = "5555"
    package var mode: ManualConnectionMode = .tcp
    package var selectedUSBSerial = ""
    package var selectedEndpoint: AdbEndpoint?
    package var activeEndpoint: AdbEndpoint?
    package var discoverySnapshot: AdbDiscoverySnapshot?
    package var discoveryStatus: DeviceDiscoveryStatus = .idle
    package var identityRestricted = true
    package var identitySessionID: UUID?
    package var identityEvidence: IdentityEvidence?
    package var presetIdentityKey: String?
    package var allowsIdentityAutomaticActions = false
    package var memoryOwnershipConfirmed = false
    package var identityConflict = false
    package var identityOperationBusy = false
    package var identityText = "设备身份尚未验证"
    package var profileMessage = ""
    package var ownershipConfirmationText = ""
    package var ownershipConfirmationToken = ""

    package var intent = ConnectionIntent()
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
        case .awaitingAuthorization: return "等待显示器确认 ADB 授权"
        case .offline(let reason): return "设备离线：\(reason)"
        case .failed(let reason): return "连接失败：\(reason)"
        }
    }

    package var discoveredDevices: [AdbDiscoveredDevice] {
        guard case .complete(let devices) = discoverySnapshot?.outcome else { return [] }
        return devices
    }

    package var discoveryText: String {
        switch discoveryStatus {
        case .discovering: return "正在枚举 ADB 设备…"
        case .failed: return "枚举未完成，请重试；未更改当前连接"
        case .idle:
            return discoverySnapshot == nil ? "尚未枚举设备" : "已发现 \(discoveredDevices.count) 个候选；请明确选择"
        }
    }

    package var transportText: String {
        if let endpoint = activeEndpoint {
            return "\(endpoint.isUSB ? "USB" : "TCP") · \(endpoint.serial)"
        }
        if mode == .usb { return selectedUSBSerial.isEmpty ? "USB · 未选择" : "USB · \(selectedUSBSerial)（未就绪）" }
        return ipInput.isEmpty ? "TCP · 未选择" : "TCP · \(ipInput):\(tcpPortInput)"
    }

    package var identityNotice: String {
        if identityConflict { return "身份或配置冲突，已停止该目标的全部设备操作" }
        if identityRestricted { return "通道身份尚未确认，预设与记忆恢复暂停" }
        if !allowsIdentityAutomaticActions { return "人工确认仅限本次会话，记忆恢复暂停" }
        if !memoryOwnershipConfirmed { return "已验证设备身份；全局记忆归属未确认，自动记忆暂停" }
        return ""
    }

}
