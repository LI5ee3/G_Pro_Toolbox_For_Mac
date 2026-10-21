import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @State private var showConnection = false
    @State private var showLogs = false
    @State private var volume = 0.0
    @State private var backlight = 0.0

    private var mode: String {
        guard let raw = state.currentValues["picture_mode"], let value = Int(raw) else { return "等待读取" }
        return RegisterMap.sceneNames[value] ?? "模式 \(value)"
    }
    private var deviceName: String {
        guard case .connected(let detail) = state.connectionStatus else { return "Redmi G Pro" }
        let name = detail.components(separatedBy: " · ").first ?? "Redmi G Pro"
        return name.hasPrefix("MiTV") || name == state.ipInput ? "Redmi G Pro" : name
    }
    private var source: String {
        let raw = state.currentValues["mitv.tvplayer.hdmi.last.source"] ?? ""
        let name = Int(raw).flatMap { RegisterMap.sourceNames[$0] } ?? state.activeSource
        return name == "DP" ? "DisplayPort" : name
    }
    private var guardian: String {
        if !state.isConnected { return "保活状态待连接" }
        return state.guardianStatus.contains("✅") ? "保活正常" : "查看保活状态"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(deviceName).font(.system(size: 23, weight: .semibold))
                            Text(state.ipInput.isEmpty ? "网络 ADB" : "网络 ADB · \(state.ipInput)")
                                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                        }
                        Spacer()
                        if state.isConnected {
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
                                Text(state.isConnected ? "画面模式" : "网络 ADB")
                                    .font(.system(size: 13)).foregroundColor(Color(red: 0.75, green: 0.8, blue: 0.88))
                                Text(state.isConnected ? mode : "等待连接")
                                    .font(.system(size: 32, weight: .medium)).foregroundColor(.white)
                                if state.isConnected {
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
                    .accessibilityLabel("显示器，\(state.isConnected ? mode : "控制尚未连接")")

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 17) {
                        HStack {
                            Label("音量", systemImage: state.dashboardMuted == true ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                            reading(state.dashboardVolumeAvailable ? state.dashboardVolume : nil)
                        }
                        FastSlider(value: $volume, range: 0...100, step: 1) { state.setDashboardVolume(Int($0)) }
                            .accessibilityLabel("显示器音量")
                            .disabled(state.dashboardVolume == nil || !state.dashboardVolumeAvailable)
                        HStack {
                            Text("0")
                            Spacer()
                            Button { state.toggleDashboardMute() } label: {
                                Label(state.dashboardMuted == true ? "解除静音" : "静音", systemImage: "speaker.slash")
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
                            reading(state.isConnected ? Int(state.currentValues["picture_backlight"] ?? "") : nil)
                        }
                        FastSlider(value: $backlight, range: 1...100, step: 1) { value in
                            state.setPictureSlider(title: "背光", value: Int(value), jniKey: "g_disp__disp_back_light",
                                                   settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
                        }
                        .accessibilityLabel("显示器背光")
                        .disabled(!state.isConnected || state.currentValues["picture_backlight"] == nil)
                        HStack {
                            Text("1")
                            Spacer()
                            Button("更多画面设置") { state.requestedPage = .picture }
                                .buttonStyle(.plain).disabled(!state.isConnected)
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
                                    RegisterMap.pictureModeGroupName(state.intValue("picture_mode", default: -1)) == RegisterMap.modeNames[value]) {
                                    state.setMode(value)
                                }
                            }
                        }
                        .disabled(!state.isConnected)
                        Button("管理预设") { state.requestedPage = .presets }
                            .font(.system(size: 13)).buttonStyle(.plain).foregroundColor(Theme.secondaryText)
                            .disabled(!state.isConnected)
                    }
                }
                .padding(24)
                .toolboxGlass(cornerRadius: 20)


                    if let error = state.dashboardVolumeError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 13)).foregroundColor(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button { state.requestedPage = .tools } label: {
                            Label(state.mediaVolumeKeysEnabled ? (state.accessibilityTrusted ? "键盘音量控制已开启" : "键盘控制需要授权") : "设置键盘音量控制", systemImage: "keyboard")
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
            if state.isConnected { state.refreshPage("picture"); state.refreshPage("source") }
        }
        .onChange(of: state.dashboardVolume) { _ in syncValues() }
        .onChange(of: state.dashboardVolumeError) { _ in syncValues() }
        .onChange(of: state.currentValues["picture_backlight"]) { _ in syncValues() }
        .onChange(of: state.isConnected) { connected in if connected { state.refreshMediaVolumeState() } }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            Label(state.isConnected ? "ADB 已连接" : state.statusText,
                  systemImage: state.isConnected ? "checkmark.circle.fill" : "wifi.slash")
                .foregroundColor(state.statusColor)
            Spacer()
            Button { state.requestedPage = .tools } label: { Label(guardian, systemImage: "checkmark.shield") }
                .help(state.guardianStatus)
            Button { state.requestedPage = .tools } label: {
                Label(state.connectionIntent.allowsAutomaticRecovery ? "唤醒后自动重连" : "自动重连已暂停", systemImage: "arrow.clockwise")
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
        volume = Double(state.dashboardVolume ?? 0)
        backlight = Double(state.intValue("picture_backlight", default: 1))
    }
}

private struct ConnectionSettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("连接显示器").font(.system(size: 24, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.toolboxAction() }
            Text("Mac 与显示器需处于可互通的网络，显示器已开启 ADB。")
                .font(.system(size: 14)).foregroundColor(Theme.secondaryText)
            SectionCard(title: "网络 ADB") {
                HStack(spacing: 12) {
                    TextField("显示器 IP 地址", text: $state.ipInput).textFieldStyle(.roundedBorder)
                        .onSubmit { state.connect() }
                    Button("开始连接") { state.connect() }.toolboxAction(prominent: true)
                }
                HStack {
                    Button("扫描内网") { state.scanNet() }.toolboxAction()
                    Button("网络诊断") { state.runDiagnostics() }.toolboxAction()
                    Spacer()
                    Button("断开连接") { state.disconnectAdb() }.toolboxAction().disabled(!state.isConnected)
                }
            }
            Picker("已扫描设备", selection: Binding(get: { state.selectedDevice }, set: { state.selectScannedDevice($0) })) {
                Text("选择扫描到的显示器").tag("")
                ForEach(state.scannedDevices, id: \.self) { device in
                    Text(state.scannedDeviceModels[device].map { "\($0) (\(device))" } ?? device).tag(device)
                }
            }
            Label(state.statusText, systemImage: state.isConnected ? "checkmark.circle" : "network")
                .foregroundColor(state.statusColor).font(.system(size: 14))
        }
        .padding(30).frame(width: 640).background(Theme.canvas).tint(Theme.accent)
    }
}

private struct OperationLogSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("操作日志").font(.system(size: 24, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.toolboxAction() }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(state.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
                .frame(height: 330).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: state.logSeq) { _ in
                    guard let last = state.logLines.indices.last else { return }
                    DispatchQueue.main.async { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            HStack {
                Toggle("记录到本地文件", isOn: Binding(get: { state.logToFileEnabled }, set: { state.toggleLogFile($0) }))
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
