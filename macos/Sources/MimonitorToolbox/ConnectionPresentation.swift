import ToolboxDomain
import SwiftUI
import ToolboxApplication

extension ConnectionModel {
    var statusColor: Color {
        switch connectionStatus {
        case .disconnected, .connecting, .scanning, .awaitingAuthorization, .offline, .failed: return Theme.warning
        case .connected: return Theme.success
        }
    }
}

extension AdbDiscoveredDevice {
    var discoveryStateText: String {
        switch state {
        case .device: return "已枚举，待验证"
        case .unauthorized: return "等待显示器授权"
        case .offline: return "设备离线"
        case .unsupported(let raw): return "不支持的状态：\(raw)"
        case .unknown(let raw): return "未知状态：\(raw)"
        }
    }

    var discoveryTransportText: String {
        if isAmbiguous { return "重复 serial，无法唯一选择" }
        switch transport {
        case .usb: return "USB"
        case .tcp: return "TCP · 请使用网络模式"
        case .unknown: return "传输类型未知"
        case .unsupported: return "不支持的传输"
        }
    }

    var canValidateAsUSB: Bool {
        guard !isAmbiguous, AdbEndpoint.supportsUSBSerial(serial) else { return false }
        switch state {
        case .device, .unauthorized, .offline: break
        case .unsupported, .unknown: return false
        }
        switch transport {
        case .usb, .unknown: return true
        case .tcp, .unsupported: return false
        }
    }

    var usbActionTitle: String { transport == .unknown ? "验证USB" : "连接" }
}
