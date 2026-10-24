import SwiftUI
import AppKit
import Observation
import ToolboxDomain
import ToolboxApplication

// S3-01 review proposal only. Lives in the existing safe Preview target.
// All device actions below use PreviewRuntime; no live adapters or system effects.
private enum S301Sample: String, CaseIterable {
    case ready = "正常连接", offline = "离线", unknown = "未知读数"
    case authorization = "等待授权", working = "执行中", failure = "连接失败"
    var runtimeScenario: PreviewRuntime.Scenario {
        switch self {
        case .ready, .working: return .connected
        case .offline: return .usbOffline
        case .unknown: return .unknown
        case .authorization: return .usbUnauthorized
        case .failure: return .disconnected
        }
    }
}

@MainActor @Observable
private final class S301Fixture {
    let runtime: PreviewRuntime
    let actions: AppCoordinator
    var sample: S301Sample
    var page = "控制台"
    var showConnection = false
    var showLogs = false
    var showOwnership = false
    var draftMode = ManualConnectionMode.tcp
    var usbSelected = false
    var host = "192.0.2.27"
    var port = "5555"
    var volume = 10.0
    var backlight = 45.0
    var values: [String: Double] = ["黑色级别": 50, "对比度": 60, "饱和度": 50, "色调": 50, "锐度": 30]
    var mode = "标准"
    var colorTemp = "标准"
    var gamut = "自动"
    var dimming = "高"
    var response = "快速"
    var dynamicDefinition = "关"
    var lightSensor = false
    var ownershipMessage = ""
    var savedMessage = ""
    var showReset = false
    var gains: [String: Double] = ["红色增益": 1024, "绿色增益": 1024, "蓝色增益": 1024]
    init(_ sample: S301Sample) {
        self.sample = sample
        runtime = PreviewRuntime()
        actions = runtime.makeState(sample.runtimeScenario)
        draftMode = actions.connection.mode
        usbSelected = actions.connection.selectedUSBSerial == "000PreviewUSB"
        if sample == .failure { actions.connection.connectionStatus = .failed("无法访问目标地址") }
    }
    var connected: Bool { actions.connection.isConnected && sample != .working }
    var readingsKnown: Bool { connected && sample != .unknown && actions.volume.dashboardVolume != nil }
    var status: String {
        if sample == .working || actions.connection.connectionStatus == .connecting { return "正在验证连接…" }
        if sample == .failure { return "连接失败" }
        if case .awaitingAuthorization = actions.connection.connectionStatus { return "等待授权" }
        if case .offline = actions.connection.connectionStatus { return "设备离线" }
        if case .failed = actions.connection.connectionStatus { return "连接失败" }
        return connected ? "已连接" : "未连接"
    }
    var symbol: String {
        if connected { return "checkmark.circle.fill" }
        return sample == .failure ? "exclamationmark.triangle.fill" : "circle.dashed"
    }
    var endpoint: String { actions.connection.activeEndpoint?.serial ?? "—" }
    func connect() {
        sample = .ready
        actions.setConnectionMode(draftMode)
        if draftMode == .usb {
            runtime.display.configureDiscovery(rows: "000PreviewUSB device usb:preview-1 model:MiTV_Preview transport_id:2")
            actions.connectUSB(serial: "000PreviewUSB")
        } else {
            actions.connection.ipInput = host
            actions.connection.tcpPortInput = port
            actions.connect()
        }
    }
    func disconnect() {
        actions.disconnectAdb()
        sample = .ready
    }
    func commitBacklight(_ value: Double) {
        actions.setPictureSlider(title: "背光", value: Int(value), jniKey: "g_disp__disp_back_light",
                                 settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
    }
}

/// Preview controls are outside the proposed product UI. Nothing is persisted.
public struct ToolboxS301Gallery: View {
    @State private var sample = S301Sample.ready
    @State private var theme = "浅色"
    @State private var surface = "主窗口"
    @State private var original = false
    @State private var compact = false
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            if original { ToolboxPreviewGallery() }
            else {
                S301Surface(sample: sample, surface: $surface)
                    .id(sample.rawValue)
            }
            Divider()
            HStack(spacing: 12) {
                Label("S3-01 · 安全 Preview", systemImage: "eye")
                Text("内存模拟").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if surface != "菜单栏" {
                    Picker("界面", selection: $surface) {
                        ForEach(["主窗口", "画面", "连接面板", "菜单栏"], id: \.self) { Text($0) }
                    }.frame(width: 150)
                    Picker("状态", selection: $sample) {
                        ForEach(S301Sample.allCases, id: \.self) { Text($0.rawValue) }
                    }.frame(width: 166)
                    Toggle("紧凑", isOn: $compact).toggleStyle(.checkbox)
                    Toggle("原界面", isOn: $original).toggleStyle(.checkbox)
                } else {
                    Button("主窗口") { surface = "主窗口" }
                }
                Picker("外观", selection: $theme) { Text("浅色").tag("浅色"); Text("深色").tag("深色") }
                    .labelsHidden().frame(width: 76)
            }.font(.system(size: 12)).padding(10).background(.bar)
        }
        .preferredColorScheme(theme == "深色" ? .dark : .light)
        .frame(minWidth: surface == "菜单栏" ? 420 : 1020, minHeight: surface == "菜单栏" ? 400 : 688)
        .onChange(of: compact) { _, small in resize(small ? NSSize(width: 1020, height: 740) : NSSize(width: 1120, height: 820)) }
        .onChange(of: surface) { _, value in resize(value == "菜单栏" ? NSSize(width: 420, height: 460) : NSSize(width: 1120, height: 820)) }
    }
    private func resize(_ size: NSSize) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "S3-01 设计提案 · 安全 Preview" }) else { return }
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true)
    }
}

private struct S301Surface: View {
    @State private var fixture: S301Fixture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var surface: String
    init(sample: S301Sample, surface: Binding<String>) {
        _fixture = State(initialValue: S301Fixture(sample))
        self._surface = surface
    }
    var body: some View {
        Group {
            if surface == "菜单栏" {
                S301MenuPanel(f: fixture, navigate: { destination in fixture.page = destination; surface = "主窗口" }).frame(width: 360).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 184, ideal: 204, max: 240)
                } detail: {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if fixture.page == "控制台" { S301Home(f: fixture) }
                                else if fixture.page == "画面" { S301Picture(f: fixture) }
                                else { S301OtherPage(page: fixture.page) }
                            }.padding(28).frame(maxWidth: 970, alignment: .leading).frame(maxWidth: .infinity)
                        }
                    }.background(Color(nsColor: .controlBackgroundColor))
                }.navigationSplitViewStyle(.balanced)
            }
        }
        .font(.system(size: 13))
        .tint(.accentColor)
        .sheet(isPresented: $fixture.showConnection) { S301Connection(f: fixture) }
        .sheet(isPresented: $fixture.showLogs) {
            VStack(alignment: .leading, spacing: 18) {
                Text("操作日志").font(.title2.bold())
                Text(fixture.actions.logs.lines.suffix(12).joined(separator: "\n")).textSelection(.enabled)
                    .font(.system(size: 13, design: .monospaced)).frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                HStack { Text("工具与设置中保留复制、导出与记录配置。").foregroundStyle(.secondary); Spacer(); Button("完成") { fixture.showLogs = false }.keyboardShortcut(.cancelAction) }
            }.padding(24).frame(width: 620)
        }
        .onAppear {
            fixture.page = surface == "画面" ? "画面" : "控制台"
            fixture.showConnection = surface == "连接面板"
        }
        .onChange(of: surface) { _, value in
            if value == "画面" { fixture.page = "画面" }
            if value == "连接面板" { fixture.showConnection = true }
        }
        .onChange(of: fixture.actions.volume.dashboardVolume) { _, value in if let value { fixture.volume = Double(value) } }
        .onDisappear { fixture.actions.stop() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: fixture.status)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("G Pro ToolBox", systemImage: "display").font(.system(size: 15, weight: .semibold)).padding(18)
            List(selection: $fixture.page) {
                Section {
                    nav("控制台", "slider.horizontal.3")
                    nav("画面", "paintpalette")
                    nav("游戏", "gamecontroller")
                    nav("信号源", "rectangle.connected.to.line.below")
                    nav("灯光", "lightbulb")
                } header: { sidebarHeading("显示器") }
                Section {
                    nav("预设", "square.stack")
                    nav("自动任务", "calendar.badge.clock")
                    nav("遥控器", "dpad")
                } header: { sidebarHeading("工作流") }
                Section {
                    nav("工具与设置", "gearshape")
                    nav("菜单栏配置", "menubar.rectangle")
                } header: { sidebarHeading("应用") }
            }.listStyle(.sidebar)
            Divider().padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 7) {
                Text("Redmi G Pro 32U").fontWeight(.medium)
                statusLabel(fixture)
                Button("连接设置…") { fixture.showConnection = true }.buttonStyle(.link)
            }.padding(18)
        }.background(.background)
    }
    private func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.7))
    }
    private func nav(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).tag(title).padding(.vertical, 3)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Text(fixture.page).font(.system(size: 17, weight: .semibold))
            Spacer()
            if fixture.connected {
                Text("\(fixture.actions.connection.activeEndpoint?.isUSB == true ? "USB" : "TCP") 控制已连接").foregroundStyle(.secondary)
            }
            Button { fixture.showLogs = true } label: { Label("日志", systemImage: "text.alignleft") }
            Button("连接设置…") { fixture.showConnection = true }.keyboardShortcut("k", modifiers: .command)
        }.padding(.horizontal, 26).frame(height: 56).background(.bar)
    }
}

@MainActor
private func statusLabel(_ f: S301Fixture) -> some View {
    Label(f.status, systemImage: f.symbol)
        .foregroundStyle(f.connected ? Color.green : Color.secondary)
        .accessibilityLabel("控制通道：\(f.status)")
}

private struct S301Home: View {
    @Bindable var f: S301Fixture
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "display").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    .frame(width: 56, height: 56).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Redmi G Pro 32U").font(.system(size: 24, weight: .semibold))
                    HStack(spacing: 14) { statusLabel(f); Text(f.connected ? f.endpoint : "没有活动控制通道").foregroundStyle(.secondary).textSelection(.enabled) }
                }
                Spacer()
            }
            if f.connected && !f.actions.connection.identityNotice.isEmpty {
                S301Notice(title: "数据归属待确认", detail: f.actions.connection.identityNotice, symbol: "person.crop.circle.badge.questionmark") {
                    Button("设备身份与数据归属…") { f.showConnection = true }
                }
            }
            if !f.connected {
                S301Notice(title: "显示器控制未连接", detail: "音量与背光暂不可调。视频画面可能仍正常显示。", symbol: "cable.connector.slash") {
                    Button("连接显示器…") { f.showConnection = true }.buttonStyle(.borderedProminent)
                }
            } else if f.sample == .unknown {
                S301Notice(title: "部分读数未知", detail: "暂时无法读取音量与背光，请重新读取。", symbol: "questionmark.circle") {
                    Button("重新读取") { f.runtime.display.unknownReadings = false; f.actions.refreshMediaVolumeState(); f.sample = .ready }
                }
            }
            VStack(alignment: .leading, spacing: 20) {
                Text("常用控制").font(.system(size: 15, weight: .semibold))
                S301QuickControl(title: "音量", symbol: "speaker.wave.2", value: $f.volume, range: 0...100, known: f.readingsKnown,
                                  commit: { f.actions.setDashboardVolume(Int($0)) }) {
                    Button(f.actions.volume.dashboardMuted == true ? "解除静音" : "静音") { f.actions.toggleDashboardMute() }
                        .disabled(!f.readingsKnown)
                }
                Divider()
                S301QuickControl(title: "背光", symbol: "sun.max", value: $f.backlight, range: 1...100, known: f.readingsKnown,
                                  commit: f.commitBacklight) {
                    Button("画面设置") { f.page = "画面" }.buttonStyle(.link)
                }
                Divider()
                HStack {
                    Label("画面模式", systemImage: "circle.lefthalf.filled").frame(width: 116, alignment: .leading)
                    Picker("画面模式", selection: $f.mode) { ForEach(["标准", "游戏", "电影"], id: \.self) { Text($0) } }
                        .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 340)
                        .disabled(!f.connected)
                        .onChange(of: f.mode) { _, value in f.actions.setMode(value == "标准" ? 14 : value == "游戏" ? 9 : 10) }
                    Spacer()
                }
            }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.6)))
            if let error = f.actions.volume.dashboardVolumeError {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("当前设置").font(.system(size: 15, weight: .semibold)).padding(.bottom, 10)
                S301InfoRow(label: "视频输入", value: f.connected ? "DisplayPort" : "未知", action: "信号源") { f.page = "信号源" }
                S301InfoRow(label: "预设", value: "无预设", action: "管理预设") { f.page = "预设" }
                S301InfoRow(label: "自动任务", value: "未启用", action: "设置时段") { f.page = "自动任务" }
            }
            HStack(spacing: 18) {
                Button { f.page = "遥控器" } label: { Label("打开遥控器", systemImage: "dpad") }
                Button { f.page = "工具与设置" } label: { Label("键盘控制与权限", systemImage: "keyboard") }
            }.buttonStyle(.link)
        }
    }
}

// Integer parameters retain clamping/rounding without rendering one tick per value.
@MainActor
private func s301IntegerValue(_ value: Binding<Double>, range: ClosedRange<Double>) -> Binding<Double> {
    Binding(get: { value.wrappedValue }, set: { value.wrappedValue = min(max($0.rounded(), range.lowerBound), range.upperBound) })
}

private struct S301QuickControl<Accessory: View>: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let known: Bool
    let commit: (Double) -> Void
    @ViewBuilder let accessory: Accessory
    var body: some View {
        HStack(spacing: 20) {
            Label(title, systemImage: symbol).fontWeight(.medium).frame(width: 96, alignment: .leading)
            VStack(spacing: 8) {
                Slider(value: s301IntegerValue($value, range: range), in: range, label: { EmptyView() }, ticks: {}, onEditingChanged: { if !$0 { commit(value) } })
                    .accessibilityLabel("显示器\(title)").accessibilityValue(known ? "\(Int(value))，最大 100" : "未知")
                    .disabled(!known)
                HStack { Text("\(Int(range.lowerBound))"); Spacer(); Text("100") }.foregroundStyle(.secondary)
            }
            Text(known ? "\(Int(value))" : "—").font(.system(size: 28, weight: .medium)).monospacedDigit().frame(width: 54, alignment: .trailing)
            accessory.frame(width: 88)
        }.padding(.vertical, 8)
    }
}

private struct S301InfoRow: View {
    let label: String
    let value: String
    let action: String
    let run: () -> Void
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 116, alignment: .leading)
            Text(value)
            Spacer()
            Button(action, action: run).buttonStyle(.link)
        }.frame(minHeight: 38).overlay(alignment: .bottom) { Divider() }
    }
}

private struct S301Picture: View {
    @Bindable var f: S301Fixture
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("画面设置").font(.system(size: 22, weight: .semibold))
                    Text("Redmi G Pro 32U · DisplayPort · 无预设").foregroundStyle(.secondary)
                }
                Spacer()
                Button { f.actions.forceRefreshPage("picture") } label: { Label("刷新读数", systemImage: "arrow.clockwise") }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("画面模式").frame(width: 116, alignment: .leading)
                    Picker("画面模式", selection: $f.mode) { ForEach(["标准", "游戏", "电影"], id: \.self) { Text($0) } }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 292)
                    Spacer()
                    Button("恢复默认…") { f.showReset = true }
                }
                Toggle("自动调整亮度", isOn: $f.lightSensor).toggleStyle(.checkbox)
                    .onChange(of: f.lightSensor) { _, value in f.actions.setLightSensor(value) }
            }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 10))
            parameterSection("基础画面") {
                parameterSlider("背光", value: $f.backlight, range: 1...100, commit: f.commitBacklight)
                ForEach(["黑色级别", "对比度", "饱和度", "色调", "锐度"], id: \.self) { title in
                    parameterSlider(title, value: Binding(get: { f.values[title] ?? 50 }, set: { f.values[title] = $0 }), range: 0...100) { value in
                        let keys = ["黑色级别": "picture_brightness", "对比度": "picture_contrast", "饱和度": "picture_saturation", "色调": "picture_hue", "锐度": "picture_sharpness"]
                        if let key = keys[title] { f.actions.setPictureSlider(title: title, value: Int(value), jniKey: nil, settingsKeys: [key]) }
                    }
                }
            }
            parameterSection("色彩") {
                optionRow("色温", value: $f.colorTemp, options: OptionLists.colorTemp)
                if f.colorTemp == "自定义" {
                    ForEach(["红色增益", "绿色增益", "蓝色增益"], id: \.self) { title in gainSlider(title) }
                }
                optionRow("色域", value: $f.gamut, options: OptionLists.gamut)
            }
            parameterSection("光影与响应") {
                optionRow("精密控光", value: $f.dimming, options: OptionLists.localDimming)
                optionRow("动态清晰度", value: $f.dynamicDefinition, options: OptionLists.dynamicDefinition)
                optionRow("灰阶响应时间", value: $f.response, options: OptionLists.responseTime)
            }
            Text("调整会在松手后提交到显示器。").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.disabled(!f.connected)
        .onChange(of: f.mode) { _, value in f.actions.setMode(value == "标准" ? 14 : value == "游戏" ? 9 : 10) }
        .confirmationDialog("恢复当前画面模式的默认设置？", isPresented: $f.showReset, titleVisibility: .visible) {
            Button("恢复默认") { f.actions.resetCurrentMode() }
            Button("取消", role: .cancel) { }
        }
    }
    private func gainSlider(_ title: String) -> some View {
        let keys: [String: String] = ["红色增益": "picture_red_gain", "绿色增益": "picture_green_gain", "蓝色增益": "picture_blue_gain"]
        let jni: [String: String] = ["红色增益": "g_video__clr_gain_r", "绿色增益": "g_video__clr_gain_g", "蓝色增益": "g_video__clr_gain_b"]
        let binding = Binding<Double>(get: { f.gains[title] ?? 1024 }, set: { f.gains[title] = $0 })
        return parameterSlider(title, value: binding, range: Double(ControlRanges.colorGain.lowerBound)...Double(ControlRanges.colorGain.upperBound)) { value in
            f.actions.setColorGain(title: title, settingsKey: keys[title]!, jniKey: jni[title]!, value: Int(value))
        }
    }
    private func parameterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 14, weight: .semibold)).padding(.bottom, 8)
            content()
        }
    }
    private func parameterSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: s301IntegerValue(value, range: range), in: range, label: { EmptyView() }, ticks: {}, onEditingChanged: { if !$0 { commit(value.wrappedValue) } })
                .accessibilityLabel(title).disabled(!f.readingsKnown)
            Text(f.readingsKnown ? "\(Int(value.wrappedValue))" : "—").monospacedDigit().frame(width: 42, alignment: .trailing)
            Text("\(Int(range.lowerBound))–\(Int(range.upperBound))").foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
        }.frame(height: 34)
    }
    private func commitOption(_ title: String, _ value: Int) {
        switch title {
        case "色温": f.actions.setColorTemp(value)
        case "色域": f.actions.setGamut(value)
        case "精密控光": f.actions.setLocalDimming(value)
        case "动态清晰度": f.actions.setDynamicDefinition(value)
        case "灰阶响应时间": f.actions.setResponseTime(value)
        default: break
        }
    }
    private func optionRow(_ title: String, value: Binding<String>, options: [Option]) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 100, alignment: .leading)
            S301OptionPicker(value: value, options: options.map(\.label), label: title) { selected in
                value.wrappedValue = selected
                if let option = options.first(where: { $0.label == selected }) { commitOption(title, option.value) }
            }.frame(width: 180, height: 28)

            Spacer()
        }.frame(height: 36)
    }
}

// Local AppKit control: fixes the option column width and keeps native keyboard behavior.
private struct S301OptionPicker: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var value: String
    let options: [String]
    let label: String
    let changed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.controlSize = .regular
        view.font = .systemFont(ofSize: 13)
        view.autoenablesItems = false
        view.target = context.coordinator
        view.action = #selector(Coordinator.selected(_:))
        view.setAccessibilityLabel(label)
        return view
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        context.coordinator.changed = changed
        if view.itemTitles != options { view.removeAllItems(); view.addItems(withTitles: options) }
        view.selectItem(withTitle: value)
        view.isEnabled = isEnabled
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: 180, height: 28)
    }
    final class Coordinator: NSObject {
        var changed: (String) -> Void
        init(_ changed: @escaping (String) -> Void) { self.changed = changed }
        @objc func selected(_ sender: NSPopUpButton) { changed(sender.titleOfSelectedItem ?? "") }
    }
}

private struct S301Connection: View {
    @Bindable var f: S301Fixture
    @FocusState private var focusHost: Bool
    @State private var details = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("连接显示器").font(.system(size: 20, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
                .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text("活动连接").fontWeight(.semibold); Spacer(); statusLabel(f) }
                        Text(f.connected ? "Redmi G Pro 32U · \(f.endpoint)" : "没有活动端点").textSelection(.enabled).id(f.endpoint)
                        if f.connected {
                            HStack { Text("控制通道：\(f.actions.connection.activeEndpoint?.isUSB == true ? "USB" : "TCP") ADB").foregroundStyle(.secondary); Spacer(); Button("断开连接") { f.disconnect() } }
                        } else if !f.actions.connection.intent.allowsAutomaticRecovery {
                            Text("已手动断开；自动恢复已暂停，点击连接后恢复。").foregroundStyle(.secondary)
                        }
                    }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("选择连接目标").fontWeight(.semibold)
                        Picker("连接方式", selection: $f.draftMode) { Text("USB 数据线").tag(ManualConnectionMode.usb); Text("TCP 网络").tag(ManualConnectionMode.tcp) }
                            .pickerStyle(.segmented)
                        if f.draftMode == .tcp {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 7) { Text("IP 地址或主机名"); TextField("", text: $f.host).accessibilityLabel("IP 地址或主机名").focused($focusHost).textFieldStyle(.roundedBorder).onSubmit { f.connect() } }
                                VStack(alignment: .leading, spacing: 7) { Text("端口"); TextField("", text: $f.port).accessibilityLabel("ADB 端口").textFieldStyle(.roundedBorder) }.frame(width: 90)
                            }
                            HStack { Button("扫描内网") { f.actions.scanNet() }; Button("诊断填写地址") { f.actions.runDiagnostics() } }
                        } else {
                            Button { f.usbSelected = true } label: {
                                HStack {
                                    Image(systemName: f.usbSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(f.usbSelected ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("MiTV Preview").fontWeight(.medium)
                                        Text("000PreviewUSB · USB").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        if f.usbSelected { Text("已选中").foregroundStyle(Color.accentColor) }
                                        Text(f.sample == .authorization ? "待授权" : f.sample == .offline ? "离线" : "可连接").foregroundStyle(.secondary)
                                    }
                                }.padding(14).frame(maxWidth: .infinity)
                                    .background(f.usbSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(f.usbSelected ? Color.accentColor : Color.secondary.opacity(0.25)))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("USB 候选 MiTV Preview，000PreviewUSB")
                                .accessibilityValue(f.usbSelected ? "已选中" : "未选中")

                            Button("刷新设备") { f.actions.refreshDevices() }
                        }
                        Text("浏览目标不会切换当前连接。连接新目标会先结束当前会话。").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if f.sample == .failure {
                        S301Notice(title: "无法连接到 \(f.host):\(f.port)", detail: "请检查地址和网络可达性。输入已保留，可诊断或重试。", symbol: "exclamationmark.triangle.fill") { EmptyView() }
                    } else if f.sample == .authorization {
                        S301Notice(title: "在显示器上允许 ADB 调试", detail: "确认显示器上的授权请求后重试。不会删除密钥或重启服务。", symbol: "person.badge.key") { EmptyView() }
                    } else if f.sample == .working {
                        HStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在验证所选端点，尚未允许设备操作…") }
                    }
                    DisclosureGroup("设备身份与数据归属", isExpanded: $details) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(f.actions.connection.identityText).textSelection(.enabled)
                            if !f.actions.connection.identityNotice.isEmpty { Text(f.actions.connection.identityNotice).foregroundStyle(.secondary) }
                            Button("确认数据归属…") { f.showOwnership = true }.disabled(!f.connected)
                            Text("保存连接偏好与确认预设、全局记忆归属分别进行。").foregroundStyle(.secondary)
                            if !f.ownershipMessage.isEmpty { Text(f.ownershipMessage) }
                        }.padding(.top, 12)
                    }
                    Text("控制通道不改变视频输入。").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Button("保存连接偏好") { f.actions.saveConnectionPreference(); f.savedMessage = f.actions.connection.profileMessage }.disabled(!f.connected)
                Spacer()
                if f.sample == .working { Button("取消连接") { f.disconnect() } }
                else {
                    Button(f.connected ? "断开并连接所选目标" : f.sample == .failure ? "重试连接" : "连接所选目标") { f.connect() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled((f.host.trimmingCharacters(in: .whitespaces).isEmpty && f.draftMode == .tcp) || (f.draftMode == .usb && !f.usbSelected))
                }
            }.padding(20)
            if !f.savedMessage.isEmpty { Text(f.savedMessage).padding(.horizontal, 24).padding(.bottom, 16) }
        }.frame(width: 620).frame(maxHeight: 700)
        .confirmationDialog("确认当前设备的数据归属", isPresented: $f.showOwnership, titleVisibility: .visible) {
            Button("仅确认预设归属") { confirmOwnership(false) }
            if f.actions.connection.identityEvidence != nil { Button("确认预设与全局记忆归属") { confirmOwnership(true) } }
            Button("取消", role: .cancel) { }
        } message: { Text("\(f.endpoint)\n\(f.actions.connection.identityText)\n确认只登记归属。身份不足时仅限本次会话，自动任务保持暂停。") }
        .onAppear { focusHost = f.draftMode == .tcp }
    }
    private func confirmOwnership(_ memories: Bool) {
        guard let session = f.actions.connection.identitySessionID else { return }
        f.actions.confirmConnectionOwnership(includeMemories: memories, expectedSessionID: session,
                                            expectedProfileToken: f.actions.connection.ownershipConfirmationToken)
        f.ownershipMessage = f.actions.connection.profileMessage
    }
}

private struct S301Notice<Action: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder let action: Action
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                action.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct S301MenuPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Bindable var f: S301Fixture
    let navigate: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Redmi G Pro 32U").font(.system(size: 15, weight: .semibold))
                    statusLabel(f)
                }
                Spacer()
                Image(systemName: "display").font(.system(size: 23)).foregroundStyle(.secondary)
            }
            Text(f.connected ? "\(f.actions.connection.activeEndpoint?.isUSB == true ? "USB" : "TCP") · \(f.endpoint)" : "没有活动控制通道")
                .foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            miniSlider("音量", symbol: "speaker.wave.2", value: $f.volume, range: 0...100) { f.actions.setDashboardVolume(Int($0)) }
            miniSlider("背光", symbol: "sun.max", value: $f.backlight, range: 1...100, commit: f.commitBacklight)
            Divider()
            HStack { Text("预设"); Spacer(); Text("无预设").foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("打开主窗口") { navigate("控制台") }.buttonStyle(.plain)
                Spacer()
                Menu("更多") {
                    Button("连接设置…") { f.showConnection = true }
                    Button("菜单栏配置…") { navigate("菜单栏配置") }
                    Divider()
                    if f.connected { Button("断开连接") { f.disconnect() } }
                    Button("退出 ToolBox") { f.actions.quit() }
                }.menuStyle(.borderlessButton).fixedSize()
            }.frame(height: 28)

        }.padding(22).frame(width: 360).background {
                if reduceTransparency { RoundedRectangle(cornerRadius: 16).fill(.background) }
                else { RoundedRectangle(cornerRadius: 16).fill(.regularMaterial) }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.65)))
    }
    private func miniSlider(_ title: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>, commit: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                if title == "音量" {
                    Button(f.actions.volume.dashboardMuted == true ? "解除静音" : "静音") { f.actions.toggleDashboardMute() }
                        .controlSize(.small).disabled(!f.readingsKnown)
                }
                Spacer()
                Text(f.readingsKnown ? "\(Int(value.wrappedValue)) / 100" : "未知").monospacedDigit()
            }
            Slider(value: s301IntegerValue(value, range: range), in: range, label: { EmptyView() }, ticks: {}, onEditingChanged: { if !$0 { commit(value.wrappedValue) } })
                .accessibilityLabel(title).disabled(!f.readingsKnown)
        }
    }
}

// Layout stubs only; the four representative surfaces above are the review scope.
private struct S301OtherPage: View {
    let page: String
    private var groups: [(String, String)] {
        switch page {
        case "游戏": return [("刷新与同步", "320Hz · FreeSync：实际值、未知状态与读取入口"), ("游戏辅助", "准星 · 动态准星 · 狙击镜 · 狙击镜夜视 · 游戏模式生效状态"), ("记忆与联动", "HDR/SDR · FreeSync · 准星联动")]
        case "信号源": return [("当前信号源", "DisplayPort"), ("切换信号源", "DP · HDMI 1 · HDMI 2 · USB-C；切换可能使画面短暂中断")]
        case "灯光": return [("炫彩灯模式", "关闭 · 照明 · 纯色 · 屏幕同色 · 七彩梦境"), ("亮度挡位", "关闭时保留记忆值；按模式说明生效条件"), ("灯光颜色", "色温与纯色选择会切换对应模式")]
        case "预设": return [("无预设", "返回原始基线"), ("预设列表", "新建 · 编辑画面 · 应用 · 重命名 · 删除 · 在菜单栏显示"), ("应用状态", "不完整应用时暂停自动保存，提供重新应用与返回无预设")]
        case "自动任务": return [("自动任务", "按时段切换预设；与连接方式无关"), ("任务列表", "开始 · 结束 · 预设 · 启用 · 顺序 · 编辑 · 删除"), ("运行状态", "当前任务 · 本轮返回目标 · 跨午夜与重叠规则")]
        case "遥控器": return [("方向与确认", "方向键 · OK"), ("常用按键", "主页 · 菜单 · 返回 · 音量 · 静音"), ("电源", "切换显示器电源状态；与方向控制分隔")]
        case "菜单栏配置": return [("快捷项", "现有 MenuBarCatalog 全部条目与预设可见性"), ("排列顺序", "拖动排序 · 上移/下移的键盘等价入口 · 恢复默认")]
        default: return [("键盘控制与权限", "组合键 · 音量/亮度键 · 输出门控 · 辅助功能 · 自动化 · 本地网络"), ("应用", "外观 · 关窗行为 · 登录项 · 日志记录/复制/导出"), ("显示器工具", "保活状态/部署 · 4K UI · APK 安装 · ADB 命令行/Shell"), ("连接配置", "保存连接偏好 · 数据归属；自动备份与恢复限制见说明"), ("关于", "项目源代码 · 原项目")]
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(page).font(.system(size: 22, weight: .semibold))
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 10) { Text(group.0).fontWeight(.semibold); Text(group.1).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Divider() }
            }
        }
    }
}

#Preview("S3-01 原生设计提案") { ToolboxS301Gallery() }
