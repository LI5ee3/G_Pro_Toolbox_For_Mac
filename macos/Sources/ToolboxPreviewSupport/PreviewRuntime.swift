import ToolboxConcurrency
import ToolboxDomain
import ToolboxApplication
import MimonitorToolbox
import AppKit
import Foundation
import MimonitorPresetCore

/// Virtual time only; never registers a RunLoop timer or sleeps a thread.
package final class ManualScheduler: RuntimeScheduling {
    private struct Entry {
        let id: UUID
        var deadline: TimeInterval
        let interval: TimeInterval?
        let action: () -> Void
    }
    private var entries: [Entry] = []
    package private(set) var time: TimeInterval = 0
    package var pendingCount: Int { entries.count }
    package func repeating(every interval: TimeInterval, commonModes: Bool,
                   _ action: @escaping () -> Void) -> RuntimeCancellation {
        let id = UUID()
        entries.append(Entry(id: id, deadline: time + interval, interval: interval, action: action))
        return RuntimeCancellation { [weak self] in self?.entries.removeAll { $0.id == id } }
    }
    package func after(_ delay: TimeInterval, work: DispatchWorkItem) {
        entries.append(Entry(id: UUID(), deadline: time + delay, interval: nil, action: { work.perform() }))
    }
    package func advance(by delta: TimeInterval) {
        let target = time + max(0, delta)
        while let next = entries.min(by: { $0.deadline < $1.deadline }), next.deadline <= target {
            entries.removeAll { $0.id == next.id }; time = next.deadline
            if let interval = next.interval {
                entries.append(Entry(id: next.id, deadline: time + interval, interval: interval, action: next.action))
            }
            next.action()
        }
        time = target
    }
}

package final class RecordingHotkeyDriver: HotkeyDriving {
    package private(set) var starts = 0
    package private(set) var stops = 0
    package private(set) var handler: ((CGEventType, CGEvent) -> Bool)?
    package func start(handler: @escaping (CGEventType, CGEvent) -> Bool, onDisabled: @escaping () -> Void) -> Bool {
        starts += 1
        self.handler = handler
        return true
    }
    package func stop() { stops += 1; handler = nil }
}

package final class RecordingFeedback: FeedbackPresenting {
    package func start() {}
    package private(set) var hints: [String] = []
    package func show(title: String, value: String) { hints.append(title + ":" + value) }
    package func show(title: String, value: String, countdown: TimeInterval) { show(title: title, value: value) }
    package func endCountdown() {}
    package func beginOperation(title: String) -> UUID { hints.append(title); return UUID() }
    package func finishOperation(token: UUID, result: HUDOperationResult, title: String?) { hints.append(String(describing: result)) }
    package func brightness(_ value: Int) -> Bool { false }
    package func volume(_ value: Int) -> Bool { false }
    package func mute(_ muted: Bool) -> Bool { false }
    package func stop() {}
}

/// In-memory display. Incoming shell text is parsed as data and is NEVER executed.
package final class PreviewDisplay: PresetDevice {
    package let identity = "192.0.2.27"
    private let lock = NSRecursiveLock()
    private var commands: [String] = []
    private var discoveryRows = "192.0.2.27:5555 device model:MiTV_Preview transport_id:1"
    private var discoveryDevicePaths: [String: String] = [:]
    package var failWrites = false
    package var unknownReadings = false
    package var volume = 10
    package var muted = false
    package var values: [String: String] = [
        "picture_mode": "14", "picture_backlight": "45", "xiaomi_picture_backlight": "45",
        "tv_picture_light_sensor": "0", "picture_brightness": "50", "picture_contrast": "60",
        "picture_saturation": "50", "picture_hue": "50", "picture_sharpness": "30",
        "picture_color_temperature": "1", "picture_red_gain": "1024", "picture_green_gain": "1024",
        "picture_blue_gain": "1024", "picture_local_dimming": "3", "picture_dynamic_definition": "0",
        "picture_response_time": "2", "tv_picture_advanced_video_color_space": "6", "freesync": "0", "mode_320": "0",
        "mitv.tvplayer.hdmi.last.source": "29", "front_sight_index": "0", "game_mode": "0",
        "mt_game_dynamic_ft": "0", "mt_game_scope": "0", "mt_game_scope_night": "0",
        "monitor_menu_fps_counter": "0", "monitor_menu_stopwatch": "0", "monitor_menu_timer": "0",
        "atmosphere_light_switcher_pm2": "4", "atmosphere_light_illumination": "9",
        "atmosphere_light_color_temp": "1", "atmosphere_light_color_value": "0"
    ]
    package var recordedCommands: [String] { lock.lock(); defer { lock.unlock() }; return commands }
    package func configureDiscovery(rows: String, devicePaths: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        discoveryRows = rows
        discoveryDevicePaths = devicePaths
    }
    package func capture() throws -> [String: String] { lock.lock(); defer { lock.unlock() }; return values }
    package func apply(_ values: [String: String]) throws -> PresetApplyReport {
        lock.lock(); defer { lock.unlock() }
        if failWrites { throw PresetError("模拟设备写入失败，可重试") }
        self.values.merge(values) { _, new in new }
        commands.append("preset.apply")
        return PresetApplyReport(applied: ["画面设置"])
    }
    package func execute(_ request: CommandRequest) -> ProcessResult {
        lock.lock(); defer { lock.unlock() }
        guard !request.cancellation.isCancelled else { return .cancelled }
        let args = request.arguments
        commands.append(args.joined(separator: " "))
        func result(_ value: String = "", _ code: Int32 = 0) -> ProcessResult { ProcessResult(output: value, exitCode: code) }
        if args == ["devices", "-l"] { return result("List of devices attached\n\(discoveryRows)\n\n") }
        if args.count >= 3, args[0] == "-s", !args[1].contains(":") {
            guard case .complete(let devices) = AdbDeviceListParser.parse("List of devices attached\n\(discoveryRows)\n\n") else {
                return result("error: malformed simulated discovery", 1)
            }
            let matches = devices.filter { $0.serial == args[1] }
            guard matches.count == 1 else { return result("error: simulated device missing or ambiguous", 1) }
            if args[2] == "get-devpath" { return result(discoveryDevicePaths[args[1]] ?? "unknown") }
            switch matches[0].state {
            case .device: break
            case .unauthorized: return result("error: device unauthorized", 1)
            case .offline: return result("error: device offline", 1)
            case .unsupported, .unknown: return result("error: unsupported simulated device state", 1)
            }
        }
        guard args.count >= 3, args[2] == "shell" else {
            if args.contains("get-state") { return result("device") }
            if args.contains("install") { return result(failWrites ? "Failure [SIMULATED]" : "Success") }
            return result("connected")
        }
        let shell = args.last ?? ""
        let decoded = shell.replacingOccurrences(of: "\\${IFS}", with: " ")
        if shell.contains("__mimonitor_probe__") { return result("__mimonitor_probe__") }
        if shell == "getprop ro.serialno" || shell == "getprop ro.boot.serialno" {
            return result(args[1] == "000PreviewOther" ? "PREVIEW-STABLE-0002" : args[1] == "000PreviewUnknown" ? "PREVIEW-STABLE-0003" : "PREVIEW-STABLE-0001")
        }
        if shell == "getprop ro.product.model" { return result("MiTV Preview") }
        if shell.hasPrefix("settings list global") { return result(values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")) }
        if unknownReadings && (shell.hasPrefix("service call audio 22") || shell.hasPrefix("service call audio 17") || shell == "settings get system volume_music_speaker") { return result("null") }
        if shell.hasPrefix("settings get ") { return result(values[String(shell.split(separator: " ").last ?? "")] ?? "0") }
        if shell.hasPrefix("service call audio 22") { return result(String(format: "Result: Parcel(00000000 %08x)", volume)) }
        if shell.hasPrefix("service call audio 17") { return result("Result: Parcel(00000000 \(muted ? "00000001" : "00000000"))") }
        if shell.hasPrefix("service call audio 12") {
            if failWrites { return result("Parcel: Exception occurred", 1) }
            let parts = shell.split(separator: " ")
            volume = Int(parts[7]) ?? volume
            return result("Result: Parcel(00000000)")
        }
        if shell.hasPrefix("service call audio 10") {
            if failWrites { return result("Parcel: Exception occurred", 1) }
            muted = shell.contains("i32 -100")
            return result("Result: Parcel(00000000)")
        }
        if failWrites && (shell.contains("settings put") || shell.contains("TvService")) { return result("error: simulated failure", 1) }
        if shell.contains("batchGet") {
            if unknownReadings && shell.contains("edid_version") { return result("") }
            var jni = Dictionary(uniqueKeysWithValues: PicturePresetPlan.jniKeys.map { ($0, "0") })
            jni.merge(["g_disp__disp_back_light": values["picture_backlight"] ?? "45", "g_video__clr_temp": "2",
                       "g_video__vid_gamut_mapping_mode": "6", "g_video__vid_local_dimming": "3",
                       "g_video__vid_od_response_time": "2", "g_video__dp_adaptive_sync": "0",
                       "g_video__freesync_switch": "0", "g_fusion_picture__dp_edid_version": "2",
                       "g_fusion_picture__hdmi_edid_version": "1"]) { _, new in new }
            return result(jni.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        }
        // Apply settings in compound commands too; no shell evaluation takes place.
        for command in decoded.components(separatedBy: ";") {
            let parts = command.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if parts.count >= 5, parts[0] == "settings", parts[1] == "put" { values[String(parts[3])] = String(parts[4]) }
        }
        if decoded.contains("MtkDirectTool ramp") {
            let parts = decoded.components(separatedBy: "MtkDirectTool ramp ")[1].split(separator: " ")
            if parts.count >= 3 { values["picture_backlight"] = String(parts[2]) }
        }
        if shell.hasPrefix("pm path") { return result("package:/mock/guardian.apk") }
        if shell.hasPrefix("pidof") { return result("27") }
        if shell.contains("service.adb.tcp.port") || shell.contains("persist.adb.tcp.port") { return result("5555") }
        if shell.contains("init.svc.adbd") { return result("running") }
        if shell.contains("persist.appcontrol_w_mask") { return result("-134250497") }
        if shell.hasPrefix("stat ") { return result("4096") }
        if shell.hasPrefix("wm size") { return result(unknownReadings ? "" : "Physical size: 1920x1080") }
        if shell.hasPrefix("wm density") { return result(unknownReadings ? "" : "Physical density: 320") }
        return result("Result: Parcel(00000000)")
    }
}

package final class PreviewRuntime {
    package enum Scenario: String, CaseIterable {
        case connected = "已连接", disconnected = "未连接", failure = "写入失败", unknown = "未知读数"
        case permissionDenied = "权限拒绝", loginApproval = "登录待批准"
        case usbConnected = "USB 已连接", usbUnauthorized = "USB 待授权", usbOffline = "USB 离线"
        case multipleDevices = "多台候选", dualTransport = "USB 与 TCP 同时在线"
        case connecting = "连接中", connectionFailure = "连接失败"
        case hdrCustom = "HDR 与 RGB"
        case workflow = "预设与任务", localSaveFailure = "本地保存失败"
    }
    package let preferences = MemoryPreferences()
    package let scheduler = ManualScheduler()
    package let display = PreviewDisplay()
    package let hotkeyDriver = RecordingHotkeyDriver()
    package let feedback = RecordingFeedback()
    private let effectLock = NSLock(), loginLock = NSLock()
    private var recordedEffects: [String] = []
    private var connectionBackups: [String: Data] = [:]
    package var connectionBackupCount: Int { effectLock.lock(); defer { effectLock.unlock() }; return connectionBackups.count }
    package var effects: [String] { effectLock.lock(); defer { effectLock.unlock() }; return recordedEffects }
    private var loginState = LoginItemStatus.notRegistered
    private var automationDenied = false
    package func environment(mode: AppEnvironment.Mode = .simulation) -> AppEnvironment {
        let resources = RuntimeResources(adbPath: "/mock/adb", serverPort: "0", runtime: { _ in nil }, guardianAPK: { "/mock/guardian.apk" })
        var system = SystemActions()
        system.backupConnectionProfile = { data, identifier in
            self.effectLock.lock(); defer { self.effectLock.unlock() }
            if let old = self.connectionBackups[identifier], old != data {
                throw PresetError("模拟备份内容冲突")
            }
            self.connectionBackups[identifier] = data
            self.recordedEffects.append("connection.backup.memory")
        }
        func record(_ name: String) { effectLock.lock(); defer { effectLock.unlock() }; recordedEffects.append(name) }
        system.isTrusted = { record("permission.read"); return false }
        system.promptAccessibility = { record("permission.prompt"); return false }
        system.openAccessibility = { record("permission.settings") }
        system.openAutomation = { record("automation.settings") }
        system.openLocalNetwork = { record("network.settings"); return true }
        system.defaultOutput = { "Mi Monitor" }
        system.scan = { [self.display.identity] }; system.subnets = { ["192.0.2"] }
        func loginSnapshot() -> LoginItemSnapshot {
            self.loginLock.lock(); defer { self.loginLock.unlock() }
            return LoginItemSnapshot(status: self.loginState)
        }
        system.loginStatus = loginSnapshot
        system.reconcileLogin = { _ in loginSnapshot() }
        system.updateLogin = { enabled, token in
            if !token.isCancelled {
                self.loginLock.lock()
                if !enabled { self.loginState = .notRegistered }
                else if self.loginState != .requiresApproval { self.loginState = .enabled }
                self.loginLock.unlock()
                record("login.write")
            }
            return loginSnapshot()
        }
        system.openLoginSettings = { record("login.settings") }
        system.applyTheme = { _ in record("theme") }
        system.copyText = { _ in record("clipboard") }
        system.openURL = { _ in record("url") }
        system.quit = { record("quit") }; system.showMainWindow = { record("window") }
        system.chooseAPK = { completion in record("apk.choose"); completion(URL(fileURLWithPath: "/mock/example.apk")) }
        system.chooseLogExport = { completion in record("log.choose"); completion(URL(fileURLWithPath: "/mock/log.txt")) }
        system.startLog = { _ in record("log.start") }; system.appendLog = { _ in record("log.append") }
        system.stopLog = { record("log.stop") }; system.exportLog = { _, _, completed in record("log.export"); completed(.success) }
        system.openLogDirectory = { record("log.open") }; system.terminal = { _, token in
            if token.isCancelled { return TerminalResult(outcome: .failed, detail: "模拟任务已取消") }
            record("terminal")
            self.loginLock.lock(); let denied = self.automationDenied; self.loginLock.unlock()
            return TerminalResult(outcome: denied ? .denied : .opened, detail: denied ? "模拟自动化拒绝 (-1743)" : "")
        }
        return AppEnvironment(mode: mode, preferences: preferences,
            adb: AdbClient(resources: resources, execute: display.execute),
            hotkeys: HotkeyManager(driver: hotkeyDriver), feedback: feedback, scheduler: scheduler,
            system: system, now: { Date(timeIntervalSince1970: 1_800_000_000 + self.scheduler.time) },
            calendar: Calendar(identifier: .gregorian), presetDevice: { _, _, identity in PreviewPresetDevice(display: self.display, identity: identity) })
    }
    @MainActor package func makeState(_ scenario: Scenario = .connected) -> AppCoordinator {
        loginLock.lock()
        loginState = scenario == .loginApproval ? .requiresApproval : .notRegistered
        automationDenied = scenario == .permissionDenied
        loginLock.unlock()
        if scenario == .workflow || scenario == .localSaveFailure {
            // Use the existing engine and in-memory device/store, never production defaults.
            let engine = PresetEngine(store: PresetStore(defaults: preferences))
            if let reading = try? engine.create(name: "日常阅读", device: display) {
                display.values["picture_mode"] = "9"
                display.values["picture_backlight"] = "25"
                display.values["xiaomi_picture_backlight"] = "25"
                if let movie = try? engine.create(name: "夜间电影 · 暖色低背光", device: display) {
                    try? engine.setMenuBarVisibility(id: PicturePreset.baselineID, visible: true)
                    try? engine.setMenuBarVisibility(id: movie.id, visible: true)
                    try? engine.saveTask(ScheduledPresetTask(presetID: reading.id, start: "18:00", end: "20:00"))
                    try? engine.saveTask(ScheduledPresetTask(presetID: movie.id, start: "23:00", end: "02:00"))
                }
            }
        }
        let state = AppCoordinator(environment: environment())
        state.settings.loginItem = LoginItemSnapshot(status: scenario == .loginApproval ? .requiresApproval : .notRegistered)
        if scenario == .permissionDenied {
            state.settings.terminalResult = TerminalResult(outcome: .denied, detail: "模拟自动化拒绝 (-1743)")
            state.keyboard.listenerStatus = .permissionRequired
        }
        state.ipInput = display.identity
        display.failWrites = scenario == .failure
        display.unknownReadings = scenario == .unknown
        if scenario == .hdrCustom {
            display.values["picture_mode"] = "11"
            display.values["picture_color_temperature"] = "3"
            display.values["settings_display_hdr_color_tone"] = "0"
        }
        let usbSerial = "000PreviewUSB"
        let usbState = scenario == .usbUnauthorized ? "unauthorized" : scenario == .usbOffline ? "offline" : "device"
        var rows = "\(display.identity):5555 device model:MiTV_Preview transport_id:1"
        switch scenario {
        case .usbConnected, .usbUnauthorized, .usbOffline:
            rows = "\(usbSerial) \(usbState) usb:preview-1 model:MiTV_Preview transport_id:2"
        case .dualTransport:
            rows += "\n\(usbSerial) device usb:preview-1 model:MiTV_Preview transport_id:2"
        case .multipleDevices:
            rows += "\n\(usbSerial) device usb:preview-1 model:MiTV_Preview transport_id:2"
            rows += "\n000PreviewOther device usb:preview-2 model:MiTV_Preview transport_id:3"
            rows += "\n000PreviewUnknown device model:MiTV_Preview transport_id:4"
            rows += "\n000PreviewDuplicate device usb:preview-5 transport_id:5"
            rows += "\n000PreviewDuplicate offline usb:preview-6 transport_id:6"
            rows += "\nemulator-5554 device model:Emulator transport_id:7"
        default: break
        }
        display.configureDiscovery(rows: rows, devicePaths: [usbSerial: "usb:preview-1", "000PreviewOther": "usb:preview-2",
                                                           "000PreviewUnknown": "usb:preview-3"])
        let isUSBScenario = [Scenario.usbConnected, .usbUnauthorized, .usbOffline, .multipleDevices, .dualTransport].contains(scenario)
        if isUSBScenario {
            state.connection.mode = .usb
            state.connection.identityRestricted = true
            let outcome = AdbDeviceListParser.parse("List of devices attached\n\(rows)\n\n")
            state.connection.discoverySnapshot = AdbDiscoverySnapshot(outcome: outcome)
            if scenario != .multipleDevices, case .complete(let devices) = outcome,
               let device = devices.first(where: { $0.serial == usbSerial }), let endpoint = AdbEndpoint.usb(discovered: device) {
                state.connection.selectedUSBSerial = usbSerial
                state.connection.selectedEndpoint = endpoint
                switch scenario {
                case .usbUnauthorized: state.connectionStatus = .awaitingAuthorization
                case .usbOffline: state.connectionStatus = .offline("USB 设备离线")
                default:
                    state.adb.beginSession(endpoint: endpoint)
                    state.connection.activeEndpoint = endpoint
                    state.connectionStatus = .connected("MiTV Preview · \(usbSerial)")
                }
            }
        } else if ![Scenario.disconnected, .connecting, .connectionFailure].contains(scenario) {
            state.connection.identityRestricted = false
            state.connection.presetIdentityKey = display.identity
            state.connection.allowsIdentityAutomaticActions = true
            state.connection.memoryOwnershipConfirmed = true
            state.connection.identityText = "已验证（内存模拟登记）"
            state.adb.ip = display.identity
            state.connection.selectedEndpoint = state.adb.endpoint
            state.connection.activeEndpoint = state.adb.endpoint
            state.connectionStatus = .connected("MiTV Preview · \(display.identity)")
        }
        if !isUSBScenario && scenario == .disconnected {
            // Original disconnected fixture represents a known simulated device, with no active channel.
            state.connection.identityRestricted = false
            state.connection.presetIdentityKey = display.identity
            state.connection.allowsIdentityAutomaticActions = true
            state.connection.memoryOwnershipConfirmed = true
        }
        if state.connection.isConnected, let endpoint = state.adb.endpoint {
            state.connection.identitySessionID = state.adb.session().sessionID
            if isUSBScenario {
                state.connection.identityEvidence = IdentityEvidence(endpoint: endpoint,
                    sessionID: state.adb.session().sessionID, sampledAt: Date(timeIntervalSince1970: 1_800_000_000),
                    stableIdentifier: "PREVIEW-STABLE-0001", roSerialno: "PREVIEW-STABLE-0001", roBootSerialno: "PREVIEW-STABLE-0001")
                state.connection.identityText = "已读取模拟稳定标识，数据归属待确认"
            }
        }
        if state.connection.isConnected {
            state.currentValues = (try? display.capture()) ?? [:]
            if scenario == .unknown {
                // A connected channel can still have no parameter snapshot.
                state.currentValues = [:]
            }
            state.loadedPages = AppCoordinator.refreshablePages
            state.seedSimulationReadings(volume: scenario == .unknown ? nil : 10, muted: scenario == .unknown ? nil : false)
        }
        if scenario == .connecting { state.connectionStatus = .connecting }
        if scenario == .connectionFailure { state.connectionStatus = .failed("模拟连接超时，请检查目标地址或显示器授权") }
        if scenario == .localSaveFailure {
            // Simulate a competing in-memory owner after the worker loaded its snapshot.
            preferences.set(Data("simulation-storage-conflict".utf8), forKey: "picture_presets_v1")
        }
        return state
    }
}

/// Preserve the real adapter boundary: compatibility ownership never changes the command target.
private struct PreviewPresetDevice: PresetDevice {
    let display: PreviewDisplay
    let identity: String
    func capture() throws -> [String: String] { try display.capture() }
    func apply(_ values: [String: String]) throws -> PresetApplyReport { try display.apply(values) }
}
