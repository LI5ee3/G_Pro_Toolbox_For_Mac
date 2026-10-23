import ToolboxDomain
import ToolboxApplication
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HomeView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PictureModel.self) private var picture
    @Environment(VolumeModel.self) private var volumeState
    @Environment(ToolsModel.self) private var tools
    @Environment(HotkeysModel.self) private var keyboard
    @State private var showConnection = false
    @State private var showLogs = false
    @State private var volume = 0.0
    @State private var backlight = 0.0

    private var mode: String {
        guard let raw = picture.currentValues["picture_mode"], let value = Int(raw) else { return "等待读取" }
        return RegisterMap.sceneNames[value] ?? "模式 \(value)"
    }
    private var deviceName: String {
        if connection.activeEndpoint?.isUSB == true { return "USB 设备" }
        guard case .connected(let detail) = connection.connectionStatus else { return "Redmi G Pro" }
        let name = detail.components(separatedBy: " · ").first ?? "Redmi G Pro"
        return name.hasPrefix("MiTV") || name == connection.ipInput ? "Redmi G Pro" : name
    }
    private var source: String {
        let raw = picture.currentValues["mitv.tvplayer.hdmi.last.source"] ?? ""
        let name = Int(raw).flatMap { RegisterMap.sourceNames[$0] } ?? picture.activeSource
        return name == "DP" ? "DisplayPort" : name
    }
    private var guardian: String {
        if !connection.isConnected { return "保活状态待连接" }
        return tools.guardianStatus.contains("✅") ? "保活正常" : "查看保活状态"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(deviceName).font(.system(size: 23, weight: .semibold))
                            Text(connection.transportText)
                                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                        }
                        Spacer()
                        if connection.isConnected {
                            Label(source, systemImage: "cable.connector")
                                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                        }
                        Button { showConnection = true } label: { Label("连接设置", systemImage: "slider.horizontal.3") }
                            .toolboxAction()
                    }

                    MonitorHardwareView {
                        ZStack {
                            LinearGradient(colors: [Color(red: 0.08, green: 0.1, blue: 0.14),
                                                    Color(red: 0.13, green: 0.17, blue: 0.24)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 12) {
                                Text(connection.isConnected ? "画面模式" : connection.transportText)
                                    .font(.system(size: 13)).foregroundColor(Color(red: 0.75, green: 0.8, blue: 0.88))
                                Text(connection.isConnected ? mode : "等待连接")
                                    .font(.system(size: 32, weight: .medium)).foregroundColor(.white)
                                if connection.isConnected {
                                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 28, height: 2).padding(.top, 4)
                                } else {
                                    Button("连接显示器") { showConnection = true }
                                        .toolboxAction(prominent: true).padding(.top, 2)
                                }
                            }
                        }
                    }
                    .frame(height: min(350, max(270, geometry.size.height - 350)))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("显示器，\(connection.isConnected ? mode : "控制尚未连接")")

                    if !connection.identityNotice.isEmpty {
                        Label(connection.identityNotice, systemImage: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 13)).foregroundColor(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Label("音量", systemImage: volumeState.dashboardMuted == true ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            reading(state.dashboardVolumeAvailable ? volumeState.dashboardVolume : nil)
                        }
                        FastSlider(value: $volume, range: ControlRanges.percentage.sliderBounds, step: 1) { state.setDashboardVolume(Int($0)) }
                            .accessibilityLabel("显示器音量")
                            .disabled(volumeState.dashboardVolume == nil || !state.dashboardVolumeAvailable)
                        HStack {
                            Text("0")
                            Spacer()
                            Button { state.toggleDashboardMute() } label: {
                                Label(volumeState.dashboardMuted == true ? "解除静音" : "静音", systemImage: "speaker.slash")
                            }.buttonStyle(.plain).disabled(!state.dashboardVolumeAvailable)
                            Spacer()
                            Text("100")
                        }.font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    }
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 115)
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Label("背光", systemImage: "sun.max").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            reading(connection.isConnected ? Int(picture.currentValues["picture_backlight"] ?? "") : nil)
                        }
                        FastSlider(value: $backlight, range: ControlRanges.backlight.sliderBounds, step: 1) { value in
                            state.setPictureSlider(title: "背光", value: Int(value), jniKey: "g_disp__disp_back_light",
                                                   settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
                        }
                        .accessibilityLabel("显示器背光")
                        .disabled(!connection.isConnected || picture.currentValues["picture_backlight"] == nil)
                        HStack {
                            Text("1")
                            Spacer()
                            Button("更多画面设置") { state.requestedPage = .picture }
                                .buttonStyle(.plain).disabled(!connection.isConnected)
                            Spacer()
                            Text("100")
                        }.font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    }
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 115)
                    VStack(alignment: .leading, spacing: 20) {
                        Label("画面模式", systemImage: "display").font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            ForEach([14, 9, 10], id: \.self) { value in
                                SelectableButton(title: RegisterMap.modeNames[value] ?? "", isSelected:
                                    RegisterMap.pictureModeGroupName(picture.intValue("picture_mode", default: -1)) == RegisterMap.modeNames[value]) {
                                    state.setMode(value)
                                }
                            }
                        }
                        .disabled(!connection.isConnected)
                        Button("管理预设") { state.requestedPage = .presets }
                            .font(.system(size: 13)).buttonStyle(.plain).foregroundColor(Theme.secondaryText)
                            .disabled(!connection.isConnected)
                    }
                }
                .padding(24)
                .toolboxGlass(cornerRadius: 20)


                    if let error = volumeState.dashboardVolumeError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 13)).foregroundColor(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button { state.requestedPage = .tools } label: {
                            Label(keyboard.mediaVolumeKeysEnabled ? (keyboard.accessibilityTrusted ? "键盘音量控制已开启" : "键盘控制需要授权") : "设置键盘音量控制", systemImage: "keyboard")
                        }
                        Spacer()
                    }
                    .font(.system(size: 13)).foregroundColor(Theme.secondaryText).buttonStyle(.plain)
                }
                .padding(.horizontal, 48).padding(.top, 18).padding(.bottom, 20)
                .frame(maxWidth: 1200).frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(isPresented: $showConnection) { ConnectionSettingsSheet() }
        .sheet(isPresented: $showLogs) { OperationLogSheet() }
        .onAppear {
            syncValues(); state.refreshMediaVolumeState()
            if connection.isConnected { state.refreshPage("picture"); state.refreshPage("source") }
        }
        .onChange(of: volumeState.dashboardVolume) { syncValues() }
        .onChange(of: volumeState.dashboardVolumeError) { syncValues() }
        .onChange(of: picture.currentValues["picture_backlight"]) { syncValues() }
        .onChange(of: connection.isConnected) { _, connected in if connected { state.refreshMediaVolumeState() } }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            Label(connection.isConnected ? "ADB 已连接" : connection.statusText,
                  systemImage: connection.isConnected ? "checkmark.circle.fill" : "wifi.slash")
                .foregroundColor(connection.statusColor)
            Spacer()
            Button { state.requestedPage = .tools } label: { Label(guardian, systemImage: "checkmark.shield") }
                .help(tools.guardianStatus)
            Button { state.requestedPage = .tools } label: {
                Label(connection.mode == .usb ? "手动 USB 模式" :
                    (connection.intent.allowsAutomaticRecovery ? "唤醒后自动重连" : "自动重连已暂停"), systemImage: "arrow.clockwise")
            }
            Button { showLogs = true } label: { Label("日志", systemImage: "text.alignleft") }
        }
        .font(.system(size: 13)).foregroundColor(Theme.secondaryText).buttonStyle(.plain)
        .padding(.horizontal, 28).frame(height: 44)
        .background(Theme.control.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke.opacity(0.6)).frame(height: 1) }
    }

    private func reading(_ value: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value.map(String.init) ?? "—").font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
            Text("/ 100").font(.system(size: 13)).foregroundColor(Theme.secondaryText)
        }
    }
    private func syncValues() {
        volume = Double(volumeState.dashboardVolume ?? 0)
        backlight = Double(picture.intValue("picture_backlight", default: 1))
    }
}

private struct ConnectionSettingsSheet: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(\.dismiss) private var dismiss
    private var isConnecting: Bool { connection.connectionStatus == .connecting }
    private var isDiscovering: Bool {
        if case .discovering = connection.discoveryStatus { return true }
        return false
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("连接显示器").font(.system(size: 24, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.toolboxAction() }
            Picker("连接方式", selection: Binding(get: { connection.mode }, set: { state.setConnectionMode($0) })) {
                ForEach(ManualConnectionMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented)
            Text("切换方式会断开当前会话；选择目标后点击连接。")
                .font(.system(size: 14)).foregroundColor(Theme.secondaryText)
            if connection.mode == .tcp {
                SectionCard(title: "网络 ADB") {
                    Text("Mac 与显示器需处于可互通的网络，显示器已开启 ADB。")
                        .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    HStack(spacing: 12) {
                        TextField("显示器 IP 地址或主机名", text: Binding(get: { connection.ipInput }, set: { connection.ipInput = $0 }))
                            .textFieldStyle(.roundedBorder).onSubmit { state.connect() }
                        TextField("端口", text: Binding(get: { connection.tcpPortInput }, set: { connection.tcpPortInput = $0 }))
                            .textFieldStyle(.roundedBorder).frame(width: 80).accessibilityLabel("显示器 ADB 端口")
                            .onSubmit { state.connect() }
                        Button("开始连接") { state.connect() }.toolboxAction(prominent: true).disabled(isConnecting)
                    }
                    HStack {
                        Button("扫描内网") { state.scanNet() }.toolboxAction()
                        Button("网络诊断") { state.runDiagnostics() }.toolboxAction()
                    }
                }
                Picker("已扫描设备", selection: Binding(get: { connection.selectedDevice }, set: { state.selectScannedDevice($0) })) {
                    Text("选择扫描到的显示器").tag("")
                    ForEach(connection.scannedDevices, id: \.self) { device in
                        Text(connection.scannedDeviceModels[device].map { "\($0) (\(device))" } ?? device).tag(device)
                    }
                }
            } else {
                SectionCard(title: "USB ADB") {
                    Text("使用 USB 数据线连接显示器，并在显示器上允许 ADB 授权。刷新列表不会自动连接。")
                        .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    HStack {
                        Text(connection.discoveryText).font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                        Spacer()
                        Button(isDiscovering ? "刷新中…" : "刷新设备") { state.refreshDevices() }
                            .toolboxAction().disabled(isDiscovering)
                    }
                    if !connection.discoveredDevices.isEmpty {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(Array(connection.discoveredDevices.enumerated()), id: \.offset) { _, device in
                                    HStack(alignment: .center, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(device.serial).font(.system(size: 13, weight: .medium, design: .monospaced)).textSelection(.enabled)
                                            Text("\(device.discoveryTransportText) · \(device.discoveryStateText)")
                                                .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                                            if connection.selectedUSBSerial == device.serial {
                                                Text("当前选择").font(.system(size: 12)).foregroundColor(Theme.accent)
                                            }
                                        }
                                        Spacer()
                                        Button(device.usbActionTitle) { state.connectUSB(serial: device.serial) }
                                            .toolboxAction().disabled(!device.canValidateAsUSB || isConnecting || isDiscovering)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 240)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label(connection.statusText, systemImage: connection.isConnected ? "checkmark.circle" : "network")
                    .foregroundColor(connection.statusColor).font(.system(size: 14))
                Text(connection.transportText).font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                if !connection.identityNotice.isEmpty {
                    Text(connection.identityNotice).font(.system(size: 13)).foregroundColor(Theme.warning)
                }
                ConnectionIdentityControls()
                HStack {
                    Spacer()
                    Button(isConnecting ? "取消连接" : "断开连接") { state.disconnectAdb() }
                        .toolboxAction().disabled(connection.connectionStatus == .disconnected)
                }
            }
        }
        .padding(30)
        }.frame(width: 700).frame(maxHeight: 850).background(Theme.canvas).tint(Theme.accent)
    }
}

private struct OperationLogSheet: View {
    @ToolboxActions var state
    @Environment(LogModel.self) private var logs
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("操作日志").font(.system(size: 24, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.toolboxAction() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(logs.lines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
                .frame(height: 330).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: logs.sequence) {
                    guard let last = logs.lines.indices.last else { return }
                    DispatchQueue.main.async { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            HStack {
                Toggle("记录到本地文件", isOn: Binding(get: { logs.recordsToFile }, set: { state.toggleLogFile($0) }))
                Spacer()
                Button("复制全部") {
                    state.copyLog()
                }
                Button("导出日志") { state.chooseLogExport() }
                Button("打开目录") { state.openLogDir() }
            }.font(.system(size: 13))
        }.padding(28).frame(width: 850).background(Theme.canvas).tint(Theme.accent)
    }
}
