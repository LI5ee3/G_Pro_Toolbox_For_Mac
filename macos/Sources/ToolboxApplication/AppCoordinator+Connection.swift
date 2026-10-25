import Foundation
import AppKit
import ToolboxDomain
import MimonitorPresetCore

extension AppCoordinator {
    package func autoConnectOnStartup() {
        guard connectionIntent.allowsStartupAttempt, connectionProfile?.error == nil else { return }
        if connectionProfile?.profile?.selectedEndpoint != nil { connect(isAuto: true); return }
        guard connection.mode == .tcp else { return }
        guard !isConnected else { return }
        let saved = (preferences.string(forKey: "saved_ip") ?? "")
            .trimmingCharacters(in: .whitespaces)
        if saved.isEmpty {
            log("启动自动连接: 未找到上次设备，开始扫描内网")
            scanNet()
            return
        }
        ipInput = saved
        log("启动自动连接: 尝试连接上次设备 \(saved)")
        connect(isAuto: true)
    }

    package func connect(isAuto: Bool = false) {
        if connection.mode == .usb { connectUSB(); return }
        let ip = ipInput.trimmingCharacters(in: .whitespaces)
        guard let endpoint = AdbEndpoint.inputTCP(host: ip, port: connection.tcpPortInput) else {
            log("请输入有效 IPv4 或 ASCII 主机名及 1–65535 端口"); return
        }
        let request = connectionIntent.beginConnection()
        resetIdentity()
        connection.selectedEndpoint = endpoint
        connection.activeEndpoint = nil
        adb.beginSession(endpoint: endpoint)
        resetMediaVolumeSession()
        invalidatePictureRefreshesForPreset()
        pendingPresetSave?.cancel(); pendingPresetSave = nil
        mediaBrightnessCommit?.cancel(); mediaBrightnessCommit = nil
        mediaBrightnessCommitInFlight = false
        mediaBrightnessPreview = nil; mediaBrightnessHardware = nil
        connectionStatus = .connecting
        if !isAuto { log("正在连接 \(ip)...") }

        submitOperation(on: connectionQueue, work: { [adb] in
            let (ok, state) = adb.ensureConnected()
            return (ok: ok, state: state, model: ok ? adb.getModel() : "")
        }) { result in
            let state = result.state, model = result.model
            let detail = model.isEmpty ? ip : "\(model) · \(ip)"
            if result.ok {
                guard self.connectionIntent.isCurrent(request) else { return }
                if !ip.isEmpty {
                    if !model.isEmpty { self.scannedDeviceModels[ip] = model }
                    if let idx = self.scannedDevices.firstIndex(of: ip) { self.scannedDevices.remove(at: idx) }
                    self.scannedDevices.insert(ip, at: 0); self.selectedDevice = ip
                }
                self.verifyConnectionIdentity(endpoint: endpoint, request: request, detail: detail)
            } else {
                guard self.connectionIntent.isCurrent(request) else { return }
                self.connection.activeEndpoint = nil
                if state.lowercased().contains("unauthorized") {
                    self.connectionStatus = .awaitingAuthorization
                    self.log("等待在显示器上确认 ADB 授权")
                    return
                }
                self.connectionStatus = isAuto ? .disconnected : .failed(state)
                if isAuto {
                    self.log("启动自动连接失败: \(state)，开始扫描内网")
                    self.scanNet()
                } else {
                    self.log("连接失败: \(state)")
                }
            }
        }
    }

    /// 进入页面时触发：懒加载该页数据 + 控制信号源轮询。
    package func onPageAppear(_ page: Page) {
        if page == .source {
            startSourcePolling()
        } else {
            stopSourcePolling()
        }
        // 记下切页时刻，用于衡量「切换 → 数据上屏」的耗时
        pageAppearTimes[page.rawValue] = environment.now()
        refreshPage(page.rawValue)
    }

    /// 该页是否必须先连接显示器（对应原版 _PAGES_NEED_CONNECTION）。
    package func needsConnection(_ page: Page) -> Bool {
        switch page {
        case .picture, .game, .source, .light, .remote: return true
        // 菜单栏配置页只改本地配置，没连显示器也能用
        case .home, .tools, .menuBar, .presets: return false
        }
    }

    package func disconnectAdb() {
        resetIdentity()
        resetMediaVolumeSession()
        pendingPresetSave?.cancel()
        pendingPresetSave = nil
        // Keep dirty identity; reconnecting this same display can still save the edit safely.
        let endpoint = adb.session().endpoint
        connectionIntent.disconnect()
        adb.beginSession(endpoint: nil)
        mediaBrightnessCommit?.cancel(); mediaBrightnessCommit = nil
        mediaBrightnessCommitInFlight = false
        mediaBrightnessPreview = nil; mediaBrightnessHardware = nil
        pendingRefreshWork?.cancel(); pendingRefreshWork = nil
        cyclePending.values.forEach { $0.work.cancel() }; cyclePending.removeAll()
        adjustPendingWork.values.forEach { $0.cancel() }; adjustPendingWork.removeAll()
        adjustPendingValues.removeAll()
        connectionStatus = .disconnected
        connection.activeEndpoint = nil
        currentValues = [:]
        loadedPages = []
        loadingPages = []
        activeSource = "未知"
        hdrLastState = nil
        stopSourcePolling()
        if let endpoint {
            runConnectionTask { _ = self.adb.disconnect(endpoint: endpoint) }
        }
        log("已断开连接")
    }

    package func scanNet(automaticallyConnect: Bool = true) {
        // The explicit connection sheet can browse TCP targets while disconnected in either mode.
        // Legacy callers retain the original mode guard and automatic selection behavior.
        guard !automaticallyConnect || connection.mode == .tcp else { log("USB 模式请使用枚举设备"); return }
        switch connectionStatus {
        case .disconnected, .awaitingAuthorization, .offline, .failed: break
        case .connecting: log("正在连接显示器，请等待连接完成或先断开"); return
        case .connected: log("已连接显示器，请先断开后扫描"); return
        case .scanning: log("正在扫描内网，请等待扫描完成"); return
        }
        let allowAutomaticSelection = automaticallyConnect && connectionIntent.allowsAutomaticRecovery
        let request = connectionIntent.beginScan()
        adb.beginSession(endpoint: nil)
        connectionStatus = .scanning
        scannedDevices = []
        scannedDeviceModels = [:]
        selectedDevice = ""
        log("开始扫描内网...")
        runConnectionTask {
            guard !self.adb.operationCancelled else { return }
            let subnets = self.environment.system.subnets()
            self.publish {
                self.log("本机网段: \(subnets.isEmpty ? "未识别" : subnets.joined(separator: ", "))")
            }
            let candidates = self.environment.system.scan()
            var found: [ScannedDevice] = []
            for ip in candidates {
                guard !self.adb.operationCancelled else { return }
                self.log("[扫描] \(ip):5555 开放，正在验证设备型号...")
                if let device = self.adb.probeScannedDevice(ip: ip) {
                    found.append(device)
                    self.log("[扫描] 已识别 \(device.label)")
                } else { self.log("[扫描] \(ip) 未通过 ADB 验证，已跳过") }
            }
            self.publish {
                guard self.connectionIntent.isCurrent(request) else { return }
                self.scannedDevices = found.map(\.ip)
                self.scannedDeviceModels = Dictionary(uniqueKeysWithValues: found.map { ($0.ip, $0.model) })
                self.connectionStatus = .disconnected
                let monitors = found.filter(\.isMonitor)
                self.log("扫描完成，发现 \(found.count) 台 ADB 设备，其中 \(monitors.count) 台 MiTV 显示器")
                if allowAutomaticSelection, let target = self.connectionIntent.scanConnectionTarget(request: request, devices: found) {
                    self.selectedDevice = target.ip
                    self.ipInput = target.ip
                    self.connection.tcpPortInput = "5555"
                    self.log("扫描识别到唯一显示器，自动连接 \(target.label)")
                    self.connect()
                } else if !automaticallyConnect {
                    self.log("扫描结果仅供选择；填写或选择目标后点击连接，未自动连接")
                } else if monitors.count > 1 {
                    self.selectedDevice = ""
                    self.ipInput = ""
                    self.log("扫描发现多台显示器，请在下拉列表中选择，选择后自动连接")
                } else {
                    self.log("未找到可自动连接的 MiTV 显示器，可手动选择或输入 IP 连接")
                }
            }
        }
    }

    package func selectScannedDevice(_ ip: String) {
        guard !ip.isEmpty else { selectedDevice = ""; return }
        if case .connecting = connectionStatus { log("正在连接显示器，请等待连接完成"); return }
        selectedDevice = ip
        ipInput = ip
        connection.tcpPortInput = "5555"
        guard !isConnected || adb.endpoint != .tcp(host: ip) else { return }
        connect()
    }


    package func startSourcePolling() {
        guard isConnected else { return }
        sourcePollArmed = true
        self.publish {
            guard self.sourcePollArmed else { return }
            self.sourcePollTimer?.invalidate()
            self.sourcePollTimer = self.environment.scheduler.repeating(every: 2, commonModes: false) { [weak self = self] in
                self?.pollSourceState()
            }
        }
    }

    package func stopSourcePolling() {
        sourcePollArmed = false
        _ = pageRefreshIntent.begin("sourcePoll")
        self.publish {
            self.sourcePollTimer?.invalidate()
            self.sourcePollTimer = nil
        }
    }

    internal func pollSourceState() {
        guard sourcePollArmed, isConnected else { stopSourcePolling(); return }
        let connectionRequest = connectionIntent.generation
        let pollRequest = pageRefreshIntent.begin("sourcePoll")
        runBackground {
            let raw = self.adb.settingsGet("mitv.tvplayer.hdmi.last.source")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let n = Int(raw), let name = RegisterMap.sourceNames[n] else { return }
            self.publish {
                guard self.sourcePollArmed, self.isConnected,
                      self.connectionIntent.isCurrent(connectionRequest),
                      self.pageRefreshIntent.isCurrent("sourcePoll", pollRequest) else { return }
                self.currentValues["mitv.tvplayer.hdmi.last.source"] = String(n)
                if self.activeSource != name {
                    self.activeSource = name
                    self.log("信号源变化: \(name)")
                }
            }
        }
    }


    /// 逐项检查连接链路的每一环，结果打到日志区。
    /// 用于区分「网段不对」「显示器无线调试没开」「权限被拦」这几类问题。
}
