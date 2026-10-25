import ToolboxDomain
import ToolboxApplication
import SwiftUI
import AppKit
import MimonitorPresetCore

/// Content of the existing MenuBarExtra; uses its shared session and user configuration.
struct MenuBarPanel: View {
    @Environment(ToolboxSession.self) private var session
    @Environment(\.openSettings) private var openSettings
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PresetsModel.self) private var presets
    @Environment(HotkeysModel.self) private var keyboard
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label(connection.deviceDisplayName, systemImage: "display").font(.system(size: 15, weight: .semibold))
                Label(connection.isConnected ? "已连接" : connection.statusText, systemImage: connection.statusSymbol)
                    .font(Theme.captionFont).foregroundStyle(connection.statusColor).lineLimit(2)
                Text(connection.activeControlText).font(Theme.captionFont).foregroundStyle(Theme.secondaryText)
                    .lineLimit(2).textSelection(.enabled)
            }.padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DashboardVolumeControl(compact: true)
                    if !keyboard.menuBarItems.isEmpty { Divider() }
                    ForEach(keyboard.menuBarItems, id: \.self) { id in
                        if let entry = MenuBarCatalog.entry(id) { MenuBarPanelRow(entry: entry) }
                    }
                    if !presets.presetConfiguration.menuBarPresets.isEmpty {
                        Divider()
                        MenuBarPresetPicker()
                    }
                    if keyboard.menuBarItems.isEmpty && presets.presetConfiguration.menuBarPresets.isEmpty {
                        Text("尚未添加参数快捷项，可在“更多”中配置。")
                            .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height.rounded(.up) }) { height in
                    if height > 0 && height != contentHeight { contentHeight = height }
                }
            }
            .frame(height: MenuBarPanelLayout.scrollHeight(contentHeight: contentHeight))
            Divider()
            HStack {
                Button("打开主窗口") { showMainWindow() }.toolboxAction()
                Spacer()
                Menu("更多") {
                    Button("连接设置…") { navigation.showsConnectionSettings = true; showMainWindow() }
                    Button("菜单栏配置…") { session.settingsPane = .menuBar; openSettings() }
                    Button("预设管理…") { state.requestedPage = .presets; showMainWindow() }
                    Button("显示器工具…") { state.requestedPage = .tools; showMainWindow() }
                    SettingsLink()
                    Divider()
                    if connection.isConnected || connection.connectionInProgress {
                        Button(connection.connectionInProgress ? "取消连接 / 扫描" : "断开当前连接") { state.disconnectAdb() }
                    } else {
                        Button("连接显示器…") { navigation.showsConnectionSettings = true; showMainWindow() }
                    }
                    Button("退出") { state.quit() }
                }.menuStyle(.borderlessButton).focusEffectDisabled().fixedSize().font(Theme.detailFont)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(6).toolboxGlass(cornerRadius: 18).tint(Theme.accent).accentColor(Theme.accent)
        .frame(width: 360).fixedSize(horizontal: false, vertical: true)
    }

    private func showMainWindow() {
        // Keep the existing Dock/window lifecycle; simulation only records the system action.
        state.showMainWindow()
        if !state.isSimulation { openWindow(id: "main") }
    }
}

/// Native segmented selection, matching the close-behavior control in app settings.
private struct MenuBarPresetPicker: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PresetsModel.self) private var presets

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预设模式").font(.callout).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                PresetSegmentedControl(
                    presets: presets.presetConfiguration.menuBarPresets,
                    selectedID: connection.isConnected && !presets.presetConfiguration.applicationIncomplete
                        ? (state.activePresetID ?? PicturePreset.baselineID) : nil,
                    isEnabled: connection.isConnected && !presets.isPresetOperationInFlight,
                    baselineEnabled: state.activePresetID == nil || state.canRestoreBaseline,
                    onSelect: { id in
                        guard id != (state.activePresetID ?? PicturePreset.baselineID)
                            || presets.presetConfiguration.applicationIncomplete else { return }
                        if id == PicturePreset.baselineID { state.restoreBaseline() }
                        else { state.applyPreset(id: id) }
                    }
                )
                .accessibilityLabel("预设模式")
                .frame(width: MenuBarPanelLayout.presetWidth(count: presets.presetConfiguration.menuBarPresets.count), height: 24)
            }
            .frame(height: 24)
            .disabled(!connection.isConnected || presets.isPresetOperationInFlight)
        }
    }
}

/// AppKit permits selectedSegment == -1: hidden presets and disconnected displays need no selection.
private struct PresetSegmentedControl: NSViewRepresentable {
    let presets: [PicturePreset]
    let selectedID: String?
    let isEnabled: Bool
    let baselineEnabled: Bool
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.focusRingType = .none
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectSegment(_:))
        return control
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: proposal.height ?? nsView.intrinsicContentSize.height)
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.ids = presets.map(\.id)
        context.coordinator.onSelect = onSelect
        control.segmentCount = presets.count
        for (index, preset) in presets.enumerated() {
            control.setLabel(preset.name, forSegment: index)
            control.setToolTip(preset.name, forSegment: index)
            control.setWidth(0, forSegment: index)
            control.setEnabled(isEnabled && (preset.id != PicturePreset.baselineID || baselineEnabled), forSegment: index)
        }
        control.selectedSegment = presets.firstIndex { $0.id == selectedID } ?? -1
        control.isEnabled = isEnabled
        control.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject {
        var ids: [String] = []
        var onSelect: ((String) -> Void)?
        @objc func selectSegment(_ control: NSSegmentedControl) {
            guard control.isEnabled, ids.indices.contains(control.selectedSegment),
                  control.isEnabled(forSegment: control.selectedSegment) else { return }
            onSelect?(ids[control.selectedSegment])
        }
    }
}

/// 面板里的单个快捷项。
private struct MenuBarPanelRow: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    let entry: MenuBarEntry

    /// 滑块拖动中的本地值：松手才下发，避免拖动过程刷出一串 ADB 命令
    @State private var dragging: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.kind {
            case .options(let options):
                let raw = state.menuBarValue(for: entry.id) ?? -1
                let current = options.contains { $0.value == raw } ? raw : -1
                Text(entry.label).font(.callout).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { current },
                    set: { state.applyMenuBarOption(entry.id, value: $0) }
                )) {
                    if current == -1 { Text("未知").tag(-1).disabled(true) }
                    ForEach(options) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.menu)
                .focusEffectDisabled()
                .labelsHidden()
                .accessibilityLabel(entry.label)
                .frame(maxWidth: .infinity, alignment: .leading)

            case .stepper(let lo, let hi, _):
                let raw = state.menuBarValue(for: entry.id)
                let reading = raw.flatMap { (lo...hi).contains($0) ? $0 : nil }
                let current = reading ?? lo
                HStack {
                    Text(entry.label).font(.callout).foregroundColor(.secondary)
                    Spacer()
                    Text((dragging ?? reading).map(String.init) ?? "—")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.primary)
                }
                // 与参数页共用原生滑块，仍只在松手时提交到原菜单动作。
                FastSlider(
                    value: Binding(
                        get: { Double(dragging ?? current) },
                        set: { dragging = Int($0.rounded()) }
                    ),
                    range: Double(lo)...Double(hi),
                    step: 1
                ) { v in
                    // 松手才提交
                    state.setMenuBarItem(entry.id, to: Int(v))
                    dragging = nil
                }
                .accessibilityLabel(entry.label)
                .accessibilityValue((dragging ?? reading).map(String.init) ?? "未知")
            }
        }
        .disabled(!connection.isConnected)
        .opacity(connection.isConnected ? 1 : 0.5)
    }
}

// 注：曾经的菜单式渲染（MenuBarMenu / MenuBarEntryMenu）已删除 ——
// 改成 .window 样式的面板后它就没有调用方了。
