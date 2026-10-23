import Foundation
import ToolboxDomain

extension AppCoordinator {
    /// A mode choice is not a connection request and must not clear manual suppression.
    package func setConnectionMode(_ mode: ManualConnectionMode) {
        guard connection.mode != mode else { return }
        disconnectAdb()
        connection.mode = mode
        connection.selectedEndpoint = nil
        resetIdentity()
    }

    /// Discovery has its own publication generation; it cannot select or take over a session.
    package func refreshDevices() {
        guard connection.discoveryStatus != .discovering else { return }
        discoveryGeneration &+= 1
        let request = discoveryGeneration
        connection.discoveryStatus = .discovering
        submitOperation(on: connectionQueue, work: { [adb] in adb.discoverDevices() }, onCancel: {
            guard self.discoveryGeneration == request else { return }
            self.connection.discoveryStatus = .idle
        }) { snapshot in
            guard self.discoveryGeneration == request else { return }
            self.connection.discoverySnapshot = snapshot
            switch snapshot.outcome {
            case .complete: self.connection.discoveryStatus = .idle
            case .failed(let reason): self.connection.discoveryStatus = .failed(reason)
            }
        }
    }

    /// S2-03 admits an explicitly chosen channel with restricted identity capabilities.
    /// Helper deployment and automatic memories/tasks are never part of this read-only probe.
    package func connectUSB(serial: String? = nil) {
        let selected = serial ?? connection.selectedUSBSerial
        guard AdbEndpoint.supportsUSBSerial(selected) else { log("请明确选择枚举中的 USB 候选"); return }
        let request = connectionIntent.beginConnection()
        resetIdentity()
        connection.mode = .usb
        connection.selectedUSBSerial = selected
        connection.selectedEndpoint = nil
        connection.activeEndpoint = nil
        connection.identityRestricted = true
        adb.beginSession(endpoint: nil)
        resetMediaVolumeSession()
        invalidatePictureRefreshesForPreset()
        pendingPresetSave?.cancel(); pendingPresetSave = nil
        pendingRefreshWork?.cancel(); pendingRefreshWork = nil
        cyclePending.values.forEach { $0.work.cancel() }; cyclePending.removeAll()
        adjustPendingWork.values.forEach { $0.cancel() }; adjustPendingWork.removeAll()
        adjustPendingValues.removeAll()
        mediaBrightnessCommit?.cancel(); mediaBrightnessCommit = nil
        mediaBrightnessCommitInFlight = false
        mediaBrightnessPreview = nil; mediaBrightnessHardware = nil
        currentValues = [:]; loadedPages = []; loadingPages = []
        activeSource = "未知"; hdrLastState = nil
        connectionStatus = .connecting
        log("正在验证 USB 候选 \(selected)…")
        submitOperation(on: connectionQueue, work: { [adb] in adb.validateUSBSelection(serial: selected) }) { result in
            guard self.connectionIntent.isCurrent(request), self.connection.mode == .usb else { return }
            self.connection.selectedEndpoint = result.endpoint
            switch result.readiness {
            case .ready:
                guard let endpoint = result.endpoint else { return }
                self.adb.beginSession(endpoint: endpoint)
                self.verifyConnectionIdentity(endpoint: endpoint, request: request, detail: "USB · \(endpoint.serial)")
            case .awaitingAuthorization:
                self.connectionStatus = .awaitingAuthorization
                self.log("请在显示器上确认 ADB 授权后重试，或取消连接")
            case .offline, .missing:
                self.connectionStatus = .offline(selected)
            case .cancelled:
                self.connectionStatus = .disconnected
            case .ambiguous:
                self.connectionStatus = .failed("相同 serial 对应多个候选，无法安全定位")
            case .unsupported:
                self.connectionStatus = .failed("无法确认 USB 类型或不支持当前设备状态")
            case .discoveryFailed:
                self.connectionStatus = .failed("设备枚举未完成，请重试")
            case .probeFailed:
                self.connectionStatus = .failed("只读探活失败，通道未就绪")
            }
        }
    }
}
