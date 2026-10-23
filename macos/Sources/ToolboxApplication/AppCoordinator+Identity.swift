import Foundation
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    internal func resetIdentity() {
        connection.identitySessionID = nil
        connection.identityEvidence = nil
        connection.presetIdentityKey = nil
        connection.identityRestricted = true
        connection.allowsIdentityAutomaticActions = false
        connection.memoryOwnershipConfirmed = false
        connection.identityConflict = false
        connection.identityText = "设备身份尚未验证"
        connection.identityOperationBusy = false
        identityOperationID = nil
    }

    internal func loadSavedConnectionProfile() {
        let snapshot = presetWorker.connectionProfileSnapshot()
        connectionProfile = snapshot
        connection.profileMessage = snapshot.error ?? snapshot.warning ?? ""
        updateOwnershipConfirmation(snapshot)
        guard snapshot.error == nil else {
            connection.identityConflict = true
            connectionIntent.disconnect()
            return
        }
        guard let endpoint = snapshot.profile?.selectedEndpoint else { return }
        connection.mode = endpoint.isUSB ? .usb : .tcp
        if endpoint.isUSB { connection.selectedUSBSerial = endpoint.serial }
        else {
            ipInput = endpoint.tcpHost
            connection.tcpPortInput = String(endpoint.tcpPort ?? 5555)
            connection.selectedEndpoint = .inputTCP(host: endpoint.tcpHost, port: connection.tcpPortInput)
        }
    }

    internal func updateOwnershipConfirmation(_ snapshot: ConnectionProfileSnapshot) {
        connection.ownershipConfirmationToken = snapshot.token
        let owners = snapshot.ownershipKeys
        connection.ownershipConfirmationText = owners.isEmpty
            ? "没有已归属的旧基线。确认后为当前设备建立独立预设身份。"
            : "旧配置所有权：\(owners.joined(separator: "、"))。确认表示这些基线与未完成任务属于当前设备；当前 IP 不是历史归属证明。"
    }

    /// The channel is ready, but device initialization waits for fresh identity resolution.
    internal func verifyConnectionIdentity(endpoint: AdbEndpoint, request: Int, detail: String) {
        let session = adb.session(), sampledAt = environment.now()
        submitOperation(on: connectionQueue, work: { [adb, presetWorker] in
            (adb.probeIdentity(endpoint: endpoint, sessionID: session.sessionID, sampledAt: sampledAt),
             presetWorker.connectionProfileSnapshot())
        }) { result in
            guard self.connectionIntent.isCurrent(request), self.adb.session().sessionID == session.sessionID else { return }
            if case .cancelled = result.0 { self.disconnectAdb(); return }
            self.connection.activeEndpoint = endpoint
            self.connectionStatus = .connected(detail)
            self.resolveConnectionIdentity(result.0, snapshot: result.1, endpoint: endpoint)
            guard self.isConnected else { return }
            self.log("通道已连接: \(endpoint.serial)；\(self.connection.identityText)")
            if self.connection.allowsIdentityAutomaticActions { self.initializeVerifiedConnection() }
        }
    }

    internal func resolveConnectionIdentity(_ probe: IdentityProbeResult,
                                           snapshot: ConnectionProfileSnapshot, endpoint: AdbEndpoint) {
        connectionProfile = snapshot
        updateOwnershipConfirmation(snapshot)
        connection.profileMessage = snapshot.error ?? snapshot.warning ?? ""
        connection.identityEvidence = nil
        connection.presetIdentityKey = nil
        connection.identityRestricted = true
        connection.allowsIdentityAutomaticActions = false
        connection.memoryOwnershipConfirmed = false
        connection.identityConflict = false
        if let error = snapshot.error { blockIdentity(error); return }
        if snapshot.ownershipKeys.count > 1 {
            blockIdentity("旧基线、活动预设或任务存在多个所有权，不能自动合并")
            return
        }
        connection.identitySessionID = adb.session().sessionID
        switch probe {
        case .cancelled: return
        case .conflict(let reason): blockIdentity(reason)
        case .unknown(let reason): connection.identityText = "身份未知：\(reason)"
        case .identified(let evidence):
            guard evidence.endpoint == endpoint, evidence.sessionID == adb.session().sessionID else {
                blockIdentity("身份读数已不属于当前会话"); return
            }
            let records = snapshot.profile?.devices ?? []
            let owners = records.filter { $0.endpoints.contains { $0.matches(endpoint) } }
            if owners.contains(where: { $0.stableIdentifier != evidence.stableIdentifier }) {
                blockIdentity("此端点的稳定标识与登记不符，可能已由另一台设备使用"); return
            }
            let matches = records.filter { $0.stableIdentifier == evidence.stableIdentifier }
            if matches.count > 1 { blockIdentity("稳定标识存在重复登记"); return }
            if endpoint.isUSB,
               observedIdentityEvidence.contains(where: { $0.endpoint.isUSB && $0.endpoint != endpoint && $0.stableIdentifier == evidence.stableIdentifier }) {
                blockIdentity("不同 USB serial 返回相同稳定标识，不能确认唯一设备"); return
            }
            if endpoint.isUSB, let record = matches.first,
               record.endpoints.contains(where: { $0.isUSB && !$0.matches(endpoint) }) {
                blockIdentity("另一个 USB serial 已登记相同标识，必须先核查冲突"); return
            }
            observedIdentityEvidence.removeAll { $0.endpoint == endpoint }
            observedIdentityEvidence.append(evidence)
            connection.identityEvidence = evidence
            guard let record = matches.first else {
                connection.identityText = "已读取稳定标识 \(evidence.stableIdentifier)，数据归属待确认"
                return
            }
            guard snapshot.ownershipKeys.allSatisfy({ $0 == record.presetIdentityKey }) else {
                blockIdentity("旧配置所有权与登记兼容键不符，保留原数据等待核查"); return
            }
            connection.presetIdentityKey = record.presetIdentityKey
            connection.identityRestricted = false
            connection.allowsIdentityAutomaticActions = true
            connection.memoryOwnershipConfirmed = snapshot.profile?.memoryOwnerDeviceID == record.deviceID
            connection.identityText = "已验证 \(evidence.stableIdentifier)；预设归属 \(record.presetIdentityKey)"
        }
        updateAutomaticTaskStatus()
        updateHdrMemoryStatus(); updateFreesyncMemoryStatus(); updateCrosshairModeStatus()
    }

    private func blockIdentity(_ reason: String) {
        disconnectAdb()
        connection.identityConflict = true
        connection.identityRestricted = true
        connection.allowsIdentityAutomaticActions = false
        connection.memoryOwnershipConfirmed = false
        connection.identityEvidence = nil
        connection.presetIdentityKey = nil
        connection.identityText = reason
        connectionStatus = .failed(reason)
        log("身份保护：\(reason)")
    }

    /// Explicit UI save. Reading or merely connecting never migrates preferences.
    package func saveConnectionPreference() {
        guard !connection.identityOperationBusy, let expected = connectionProfile else { return }
        let endpoint = connection.mode == .usb ? connection.selectedEndpoint
            : AdbEndpoint.inputTCP(host: ipInput.trimmingCharacters(in: .whitespaces), port: connection.tcpPortInput)
        guard let endpoint else { log("请先明确选择有效端点"); return }
        let session = adb.session(), operation = UUID()
        connection.identityOperationBusy = true; identityOperationID = operation
        submitOperation(on: deviceQueue, work: { [presetWorker, environment] in
            Result { try presetWorker.saveConnectionPreference(endpoint: endpoint, expected: expected,
                backup: environment.system.backupConnectionProfile,
                validateCurrent: { if session.cancellation.isCancelled { throw CancellationError() } }) }
        }, onCancel: { self.finishIdentityOperation(operation) }) { result in
            guard self.identityOperationID == operation else { return }
            self.finishIdentityOperation(operation)
            switch result {
            case .success(let snapshot):
                self.connectionProfile = snapshot
                self.updateOwnershipConfirmation(snapshot)
                self.connection.profileMessage = snapshot.warning ?? "连接偏好已保存；当前会话保持不变"
            case .failure(let error):
                self.connection.profileMessage = "连接偏好未提交：\(error.localizedDescription)"
                if case ConnectionProfileError.staleSnapshot = error { return }
                self.blockIdentity(error.localizedDescription)
            }
        }
    }

    /// Called only after the UI has presented the exact endpoint and old ownership to confirm.
    package func confirmConnectionOwnership(includeMemories: Bool, expectedSessionID: UUID, expectedProfileToken: String) {
        guard isConnected, !connection.identityConflict, !connection.identityOperationBusy,
              let endpoint = connection.activeEndpoint, let expected = connectionProfile, expected.error == nil,
              expected.ownershipKeys.count <= 1 else { return }
        let session = adb.session(), request = connectionIntent.generation, operation = UUID()
        guard session.sessionID == expectedSessionID, connection.identitySessionID == expectedSessionID else {
            log("会话已变化，请重新查看并确认归属"); return
        }
        guard expected.token == expectedProfileToken else {
            connection.profileMessage = "确认内容已变化，请重新查看并确认归属"; return
        }
        let evidence = connection.identityEvidence
        if evidence == nil, !connection.identityRestricted, connection.presetIdentityKey != nil {
            connection.profileMessage = "本次会话归属已经确认，未重复生成身份"
            return
        }
        connection.identityOperationBusy = true; identityOperationID = operation
        submitOperation(on: deviceQueue, work: { [presetWorker, environment] in
            Result { () throws -> ConnectionProfileSnapshot in
                if session.cancellation.isCancelled { throw CancellationError() }
                if let evidence {
                    guard evidence.sessionID == session.sessionID, evidence.endpoint == endpoint else { throw CancellationError() }
                    return try presetWorker.bindConnectionIdentity(evidence: evidence, expected: expected,
                        confirmLegacyOwnership: true, confirmMemories: includeMemories,
                        backup: environment.system.backupConnectionProfile,
                        validateCurrent: { if session.cancellation.isCancelled { throw CancellationError() } })
                }
                let fresh = presetWorker.connectionProfileSnapshot()
                if let error = fresh.error { throw PresetError(error) }
                guard fresh.ownershipKeys == expected.ownershipKeys, fresh.profile == expected.profile else {
                    throw PresetError("配置归属或设备登记已改变，请重新审查后确认")
                }
                guard fresh.token == expected.token else { throw ConnectionProfileError.staleSnapshot }
                return fresh
            }
        }, onCancel: { self.finishIdentityOperation(operation) }) { result in
            guard self.identityOperationID == operation, self.connectionIntent.isCurrent(request),
                  self.adb.session().sessionID == session.sessionID else { return }
            self.finishIdentityOperation(operation)
            switch result {
            case .failure(let error):
                self.connection.profileMessage = "身份确认未提交：\(error.localizedDescription)"
                if case ConnectionProfileError.staleSnapshot = error { return }
                self.blockIdentity(error.localizedDescription)
            case .success(let snapshot):
                if let evidence { self.resolveConnectionIdentity(.identified(evidence), snapshot: snapshot, endpoint: endpoint) }
                else {
                    self.connection.presetIdentityKey = snapshot.ownershipKeys.first ?? "device:\(UUID().uuidString.lowercased())"
                    self.connection.identityRestricted = false
                    self.connection.allowsIdentityAutomaticActions = false
                    self.connection.memoryOwnershipConfirmed = false
                    self.connection.identityText = "人工确认（仅当前会话）；重连必须再次确认"
                }
                self.connection.profileMessage = snapshot.warning ?? "归属已确认；本次确认未部署组件或执行设备设置"
                self.updateAutomaticTaskStatus()
            }
        }
    }

    private func finishIdentityOperation(_ operation: UUID) {
        guard identityOperationID == operation else { return }
        identityOperationID = nil; connection.identityOperationBusy = false
    }

    internal func initializeVerifiedConnection() {
        guard isConnected, connection.allowsIdentityAutomaticActions else { return }
        let request = connectionIntent.generation, session = adb.session()
        submitOperation(on: connectionQueue, work: { [adb] in adb.ensureJars() }) { _ in
            guard self.isConnected, self.connectionIntent.isCurrent(request),
                  self.adb.session().sessionID == session.sessionID, self.connection.allowsIdentityAutomaticActions else { return }
            self.loadedPages = []; self.loadingPages = []; self.activeSource = "未知"; self.hdrLastState = nil
            self.refreshPage("picture"); self.refreshPage("game")
            self.pollHdrState(force: true); self.checkAutomaticTasks(); self.check4KState()
            self.checkGuardian(); self.refreshMediaVolumeState()
        }
    }
}
