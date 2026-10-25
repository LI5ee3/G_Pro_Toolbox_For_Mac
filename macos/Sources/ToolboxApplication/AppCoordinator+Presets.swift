import ToolboxDomain
import AppKit
import Foundation
import MimonitorPresetCore

extension AppCoordinator {
    package var activePresetID: String? {
        _ = connection.connectionStatus
        guard !connection.identityRestricted else { return nil }
        return presetConfiguration.activeDeviceIdentity == (connection.presetIdentityKey ?? "") ? presetConfiguration.activePresetID : nil
    }
    package var activePresetName: String {
        presetConfiguration.presets.first { $0.id == activePresetID }?.name ?? "无预设"
    }
    package var presetControlPolicy: PresetControlPolicy {
        _ = connection.connectionStatus
        return PresetControlPolicy(configuration: presetConfiguration, deviceIdentity: (connection.presetIdentityKey ?? ""), isSwitching: isPresetBusy)
    }
    package var memoriesSuspendedByPreset: Bool { !connection.memoryOwnershipConfirmed || !connection.allowsIdentityAutomaticActions || presetControlPolicy.memoriesLocked }
    package var effectiveHdrMemoryEnabled: Bool {
        !memoriesSuspendedByPreset && presetControlPolicy.effectiveMemoryEnabled(savedPreference: hdrMemoryEnabled)
    }
    package var effectiveFreesyncMemoryEnabled: Bool {
        !memoriesSuspendedByPreset && presetControlPolicy.effectiveMemoryEnabled(savedPreference: freesyncMemoryEnabled)
    }
    package var canRestoreBaseline: Bool {
        !connection.identityRestricted && isConnected && presetConfiguration.baseline?.deviceIdentity == (connection.presetIdentityKey ?? "")
            && !(presetConfiguration.baseline?.values.isEmpty ?? true)
    }

    package func startPresetFeatures() {
        submitOperation(on: deviceQueue, work: { self.presetWorker.withEngine { $0.configuration } }) {
            self.presetConfiguration = $0
        }
        if let error = presetWorker.loadError { presetError = error; log(error) }
    }

    /// Resume a dirty preset after reconnecting to its confirmed display.
    internal func resumePendingPresetSave() {
        guard connection.allowsIdentityAutomaticActions, !connection.identityRestricted, isConnected,
              !isPresetOperationInFlight, !presetConfiguration.applicationIncomplete,
              presetWorker.loadError == nil, pendingPresetSave == nil,
              let id = pendingPresetSaveID, activePresetID == id,
              pendingPresetSaveDevice == connection.presetIdentityKey else { return }
        schedulePresetSave(id: id, request: connectionIntent.generation, revision: pictureEditRevision, delay: 1.2)
    }

    package func createPreset(name: String) {
        runPresetOperation("新建预设", navigateToPicture: true) { engine, device in
            guard let device else { throw PresetError("请先连接显示器") }
            try engine.create(name: name, device: device)
        }
    }
    package func applyPreset(id: String, edit: Bool = false) {
        if edit && activePresetID == id && !isPresetOperationInFlight && !presetConfiguration.applicationIncomplete {
            requestedPage = .picture
            return
        }
        let name = presetConfiguration.presets.first { $0.id == id }?.name ?? "预设"
        runPresetOperation("应用预设", refresh: true, navigateToPicture: edit,
                           switchHUDTitle: "预设：\(name)") { engine, device in
            guard let device else { throw PresetError("请先连接显示器") }
            try engine.apply(id: id, device: device)
        }
    }
    package func restoreBaseline(edit: Bool = false) {
        if edit && isConnected && activePresetID == nil && !isPresetOperationInFlight
            && !presetConfiguration.applicationIncomplete {
            requestedPage = .picture
            return
        }
        runPresetOperation("应用无预设", refresh: true, navigateToPicture: edit,
                           switchHUDTitle: "预设：无预设") { engine, device in
            guard let device else { throw PresetError("请先连接显示器") }
            try engine.restore(device: device)
        }
    }
    package func renamePreset(id: String, name: String) {
        runPresetOperation("重命名预设", requiresIdentity: false, flushAutosave: false) { engine, _ in try engine.rename(id: id, name: name) }
    }
    package func setPresetMenuBarVisibility(id: String, visible: Bool) {
        runPresetOperation("更新预设菜单栏显示", requiresIdentity: false, flushAutosave: false) { engine, _ in
            try engine.setMenuBarVisibility(id: id, visible: visible)
        }
    }
    package func deletePreset(id: String) {
        let hudTitle = presetConfiguration.activePresetID == id ? "预设：无预设" : nil
        runPresetOperation("删除预设", refresh: true, switchHUDTitle: hudTitle) { engine, device in
            try engine.delete(id: id, device: device)
        }
    }
    /// Every picture write (including hotkeys and menu-bar controls) goes through this path.
    /// Capture the preset identity NOW, not when the delayed readback eventually runs.
    package func runPictureChange(delay: TimeInterval = 1.2, completion: (() -> Void)? = nil, _ work: @escaping @Sendable () -> Void) {
        guard isConnected, !isPresetBusy, !presetConfiguration.applicationIncomplete else { completion?(); return }
        let request = connectionIntent.generation
        let identity = (connection.presetIdentityKey ?? "")
        let presetID = activePresetID
        pictureEditRevision &+= 1
        let revision = pictureEditRevision
        if presetID != nil { pendingPresetSaveID = presetID; pendingPresetSaveDevice = identity }
        pendingPresetSave?.cancel()
        pendingPresetSave = nil
        runBackground {
            let current = !self.adb.operationCancelled
            guard current else { self.publish { completion?() }; return }
            self.adb.transaction(work)
            self.deviceWorkState.pictureSettleUntil = Date().addingTimeInterval(delay)
            self.publish {
                if self.connectionIntent.isCurrent(request), (self.connection.presetIdentityKey ?? "") == identity,
                   self.activePresetID == presetID, self.pictureEditRevision == revision,
                   !self.isPresetBusy, let presetID {
                    self.schedulePresetSave(id: presetID, request: request, revision: revision, delay: delay)
                }
                completion?()
            }
        }
    }

    internal func schedulePresetSave(id: String, request: Int, revision: Int, delay: TimeInterval) {
        let save = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPresetSave = nil
            guard !self.connection.identityRestricted, self.isConnected,
                  self.connectionIntent.isCurrent(request), self.activePresetID == id,
                  self.pictureEditRevision == revision, !self.presetConfiguration.applicationIncomplete else { return }
            if self.hasPendingDeviceControls || self.isPresetOperationInFlight {
                self.schedulePresetSave(id: id, request: request, revision: revision, delay: 0.5)
                return
            }
            self.runPresetOperation("自动保存当前预设", autosave: true, flushAutosave: false) { engine, device in
                guard let device else { throw PresetError("显示器暂不可用，待连接恢复后保存") }
                try engine.synchronize(id: id, device: device)
            }
        }
        pendingPresetSave = save
        environment.scheduler.after(delay, work: save)
    }

    internal func runPresetOperation(_ label: String, autosave: Bool = false, refresh: Bool = false, requiresIdentity: Bool = true,
                                    navigateToPicture: Bool = false, flushAutosave: Bool = true,
                                    switchHUDTitle: String? = nil,
                                    operation: @escaping @Sendable (PresetEngine, (any PresetDevice)?) throws -> Void) {
        guard !isPresetOperationInFlight else { return }
        guard !requiresIdentity || !connection.identityRestricted else { log(connection.identityNotice); return }
        let request = connectionIntent.generation
        let identity = (connection.presetIdentityKey ?? "")
        let connected = requiresIdentity && isConnected
        let saveID = requiresIdentity && pendingPresetSaveDevice == identity ? pendingPresetSaveID : nil
        pendingPresetSave?.cancel()
        pendingPresetSave = nil
        if saveID != nil { pendingPresetSaveID = nil; pendingPresetSaveDevice = nil }
        isPresetOperationInFlight = true
        isPresetBusy = refresh || navigateToPicture
        presetOperationText = label
        // 预设直接写 JNI+settings，不走 setPictureSlider，
        // 所以这里丢掉背光预览，下次亮度键以新的设备值为准。
        mediaBrightnessPreview = nil
        mediaBrightnessHardware = nil
        if refresh || navigateToPicture { invalidatePictureRefreshesForPreset() }
        let operationID = UUID()
        presetOperationID = operationID
        let hudToken = switchHUDTitle.map { environment.feedback.beginOperation(title: $0) }
        updateHdrMemoryStatus()
        updateFreesyncMemoryStatus()

        runBackground(onCancel: {
            guard self.presetOperationID == operationID else { return }
            self.presetOperationID = nil
            self.isPresetOperationInFlight = false; self.isPresetBusy = false; self.presetOperationText = ""
            self.updateHdrMemoryStatus(); self.updateFreesyncMemoryStatus()
            if let hudToken { self.environment.feedback.finishOperation(token: hudToken, result: .cancelled, title: nil) }
        }) {
            let current = !self.adb.operationCancelled
            // submitOperation captured this immutable session on MainActor before queueing.
            // Do not re-read the mutable client endpoint or derive an address from identity.
            let device = connected && current
                ? self.environment.presetDevice(self.adb, self.adb.operationSession?.endpoint, identity) : nil
            let ((reports, errorText, savedEdits, configuration), profile) = self.presetWorker.withEngineAndProfileSnapshot { engine in
                var reports: [PresetApplyReport] = []
                engine.onReport = { reports.append($0) }
                var errorText: String?
                var savedEdits = saveID == nil
                do {
                    try self.adb.transaction {
                        if device != nil, Date() < self.deviceWorkState.pictureSettleUntil {
                            guard self.adb.pause(self.deviceWorkState.pictureSettleUntil.timeIntervalSinceNow) else { throw CancellationError() }
                        }
                        if flushAutosave, let saveID, let device {
                            // Never save mixed values from a failed application into the original preset.
                            if !engine.configuration.applicationIncomplete {
                                try engine.synchronize(id: saveID, device: device)
                            }
                            savedEdits = true
                        }
                        try self.adb.checkCancellation()
                        try operation(engine, device)
                        if !flushAutosave { savedEdits = true }
                    }
                } catch { errorText = error.localizedDescription }
                engine.onReport = nil
                return (reports, errorText, savedEdits, engine.configuration)
            }

            self.publishCompletion {
                guard self.presetOperationID == operationID else { return }
                self.presetOperationID = nil
                self.presetConfiguration = configuration
                if errorText == nil {
                    self.connectionProfile = profile
                    self.updateOwnershipConfirmation(profile)
                }
                self.isPresetOperationInFlight = false
                self.isPresetBusy = false
                self.presetOperationText = ""
                self.updateHdrMemoryStatus()
                self.updateFreesyncMemoryStatus()
                if !savedEdits, let saveID,
                   configuration.activePresetID == saveID, configuration.activeDeviceIdentity == identity,
                   self.pendingPresetSaveID == nil || (self.pendingPresetSaveID == saveID && self.pendingPresetSaveDevice == identity) {
                    self.pendingPresetSaveID = saveID
                    self.pendingPresetSaveDevice = identity
                    if self.pendingPresetSave == nil, self.isConnected, (self.connection.presetIdentityKey ?? "") == identity,
                       !configuration.applicationIncomplete {
                        self.schedulePresetSave(id: saveID, request: self.connectionIntent.generation, revision: self.pictureEditRevision, delay: 3)
                    }
                }
                if let errorText {
                    if !autosave || errorText != self.lastPresetAutosaveError {
                        self.log("\(label)失败：\(errorText)")
                    }
                    if autosave { self.lastPresetAutosaveError = errorText }
                    else { self.presetError = errorText }
                } else {
                    self.lastPresetAutosaveError = ""
                    self.log("\(label)完成")
                    for report in reports {
                        self.log(report.summary)
                        for skipped in report.skipped { self.log("跳过：\(skipped)") }
                    }
                    if navigateToPicture, self.connectionIntent.isCurrent(request), self.isConnected {
                        self.requestedPage = .picture
                    }
                }
                if refresh, self.isConnected, self.connectionIntent.isCurrent(request) {
                    self.forceRefreshPage("picture")
                    self.forceRefreshPage("game")
                }
                if let hudToken {
                    let result = HUDOperationResult.completion(
                        isCurrentConnection: self.isConnected && self.connectionIntent.isCurrent(request) && (self.connection.presetIdentityKey ?? "") == identity,
                        hasError: errorText != nil, verifiedApplications: reports.map { $0.ok })
                    self.environment.feedback.finishOperation(token: hudToken, result: result,
                                                    title: result == .success ? "预设：\(self.activePresetName)" : nil)
                }
                self.resumePendingPresetSave()
            }
        }
    }
}
