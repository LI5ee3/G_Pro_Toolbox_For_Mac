import SwiftUI
import ToolboxDomain
import ToolboxApplication

struct ConnectionSettingsSheet: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(LogModel.self) private var logs
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ConnectionDraft
    @State private var showsDiagnostics = false
    @FocusState private var hostFocused: Bool

    init(connection: ConnectionModel) {
        _draft = State(initialValue: ConnectionDraft(connection: connection))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("连接设置").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }.toolboxAction().keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    activeConnection
                    Divider()
                    Text("选择连接目标").font(Theme.sectionFont)
                    Picker("控制传输", selection: $draft.mode) {
                        ForEach(ManualConnectionMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).focusEffectDisabled()
                    Text("浏览和选择只编辑草稿；点击下方连接按钮后才结束旧会话并连接所选目标。USB ADB 与 USB-C 视频输入分别设置。")
                        .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                    if draft.mode == .tcp { tcpTarget } else { usbTargets }
                    Divider()
                    DisclosureGroup("设备身份与数据归属") { ConnectionIdentityControls().padding(.top, 10) }
                        .font(Theme.sectionFont)
                    DisclosureGroup("操作日志", isExpanded: $showsDiagnostics) {
                        Text(logs.lines.suffix(16).joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Theme.control, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }.font(Theme.detailFont)
                }.padding(20)
            }
            Divider()
            HStack {
                Button(connection.connectionInProgress ? "取消连接 / 扫描" : "断开当前连接") { state.disconnectAdb() }
                    .toolboxAction().disabled(connection.connectionStatus == .disconnected)
                Spacer()
                Button(connection.isConnected ? "断开并连接所选目标" : "连接所选目标") { draft.connect(using: state) }
                    .toolboxAction(prominent: true).keyboardShortcut(.defaultAction)
                    .disabled(!draft.canConnect(connection))
            }.padding(20)
        }
        .frame(width: 620, height: 620).background(Theme.canvas).tint(Theme.accent)
        .onAppear { hostFocused = draft.mode == .tcp }
        .onChange(of: draft.mode) { _, mode in hostFocused = mode == .tcp }
    }

    private var activeConnection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活动连接").font(Theme.sectionFont)
            HStack {
                if connection.connectionInProgress { ProgressView().controlSize(.small) }
                Label(connection.statusText, systemImage: connection.statusSymbol)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(connection.statusColor)
            }
            LabeledContent("ADB 控制") { Text(connection.activeControlText).textSelection(.enabled) }
                .font(Theme.detailFont)
            Text(connection.recoveryText).font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
            if !connection.identityNotice.isEmpty {
                Label(connection.identityNotice, systemImage: "person.crop.circle.badge.questionmark")
                    .font(Theme.detailFont).foregroundStyle(Theme.warning)
            }
        }
    }

    private var tcpTarget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("主机名或 IP 地址").font(Theme.controlFont)
                    TextField("显示器地址", text: $draft.host).textFieldStyle(.roundedBorder).focused($hostFocused)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("ADB 端口").font(Theme.controlFont)
                    TextField("端口", text: $draft.port).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("显示器 ADB 端口")
                }.frame(width: 90)
            }
            HStack {
                Button("扫描内网") { state.scanNet(automaticallyConnect: false) }.toolboxAction()
                    .disabled(connection.isConnected || connection.activeEndpoint != nil || connection.connectionInProgress)
                Button("诊断填写地址") { draft.diagnose(using: state); showsDiagnostics = true }.toolboxAction()
            }
            if connection.isConnected || connection.activeEndpoint != nil {
                Text("当前连接保持使用；断开后可扫描内网，也可直接填写下一个目标。")
                    .font(Theme.captionFont).foregroundStyle(Theme.secondaryText)
            }
            if connection.connectionStatus == .scanning {
                HStack { ProgressView().controlSize(.small); Text("正在扫描，结果不会自动连接…") }.font(Theme.detailFont)
            }
            if !connection.scannedDevices.isEmpty {
                List(selection: Binding<String?>(
                    get: { draft.port == "5555" && connection.scannedDevices.contains(draft.host) ? draft.host : nil },
                    set: { host in
                        guard let host, connection.scannedDevices.contains(host) else { return }
                        draft.host = host; draft.port = "5555"
                    }
                )) {
                    ForEach(connection.scannedDevices, id: \.self) { host in
                        HStack {
                            Text(connection.scannedDeviceModels[host] ?? host)
                            Spacer()
                            Text("\(host):5555").foregroundStyle(Theme.secondaryText)
                        }.font(Theme.detailFont).tag(host)
                    }
                }
                .listStyle(.inset).environment(\.defaultMinListRowHeight, 44)
                .frame(height: min(CGFloat(connection.scannedDevices.count) * 44 + 8, 184))
                .accessibilityLabel("扫描到的 TCP 设备")
            }
        }
    }

    private var usbTargets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if case .failed = connection.discoveryStatus {
                    Label(connection.discoveryText, systemImage: "exclamationmark.triangle")
                        .font(Theme.detailFont).foregroundStyle(Theme.warning)
                } else {
                    Text(connection.discoveryText).font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("刷新设备") { state.refreshDevices() }.toolboxAction()
                    .disabled(connection.discoveryStatus == .discovering || connection.connectionInProgress)
            }
            Text("连接 USB 数据线，并在显示器上允许 ADB 授权。枚举只读取列表，不切换当前控制通道。")
                .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
            if !connection.discoveredDevices.isEmpty {
                List(selection: Binding<String?>(
                    get: { connection.discoveredDevices.contains { $0.serial == draft.usbSerial && $0.canValidateAsUSB } ? draft.usbSerial : nil },
                    set: { serial in
                        guard !connection.connectionInProgress, let serial,
                              connection.discoveredDevices.contains(where: { $0.serial == serial && $0.canValidateAsUSB }) else { return }
                        draft.usbSerial = serial
                    }
                )) {
                    ForEach(Array(connection.discoveredDevices.enumerated()), id: \.offset) { _, device in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.serial).font(Theme.controlFont)
                                Text("\(device.discoveryTransportText) · \(device.discoveryStateText)")
                                    .font(Theme.captionFont).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            if device.transport == .unknown { Text("需验证 USB").font(Theme.captionFont) }
                        }
                        .tag(device.serial)
                        .disabled(!device.canValidateAsUSB || connection.connectionInProgress)
                        .selectionDisabled(!device.canValidateAsUSB || connection.connectionInProgress)
                    }
                }
                .listStyle(.inset).environment(\.defaultMinListRowHeight, 52)
                .frame(height: min(CGFloat(connection.discoveredDevices.count) * 52 + 8, 216))
                .accessibilityLabel("发现的 ADB 设备")
            }
        }
    }
}
