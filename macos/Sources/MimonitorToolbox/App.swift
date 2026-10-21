import ToolboxDomain
import ToolboxApplication
import SwiftUI
import AppKit
import MimonitorPresetCore

/// 菜单栏下方面板。比系统菜单自由得多 —— 能放滑块、分组、任意布局。
struct MenuBarPanel: View {
    @ToolboxActions var state
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 状态行
            HStack(spacing: 8) {
                Circle()
                    .fill(state.connection.statusColor)
                    .frame(width: 8, height: 8)
                Text(state.statusText)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            if state.menuBarItems.isEmpty && state.presetConfiguration.menuBarPresets.isEmpty {
                Text("还没有添加快捷项。\n去「菜单栏」或「预设模式」页添加。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !state.presetConfiguration.menuBarPresets.isEmpty {
                            MenuBarPresetPicker()
                        }
                        ForEach(state.menuBarItems, id: \.self) { id in
                            if let entry = MenuBarCatalog.entry(id) {
                                MenuBarPanelRow(entry: entry)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: MenuBarContentHeightKey.self, value: geometry.size.height)
                        }
                    }
                }
                .frame(height: MenuBarPanelLayout.scrollHeight(contentHeight: contentHeight))
                .onPreferenceChange(MenuBarContentHeightKey.self) { height in
                    let measured = height.rounded(.up)
                    if measured > 0 && measured != contentHeight { contentHeight = measured }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("显示主窗口") {
                    // 先切回 .regular 再开窗：此时应用可能正处于 .accessory
                    // （Dock 里没有图标），不先切的话窗口能开出来但 Dock 图标要等一拍
                    state.environment.system.showMainWindow()
                    if state.environment.mode == .live { openWindow(id: "main") }
                }
                if state.isConnected {
                    Button("断开") { state.disconnectAdb() }
                } else {
                    Button("重连") { state.connect() }
                }
                Spacer()
                Button("退出") { state.environment.system.quit() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .padding(6)
        .toolboxGlass(cornerRadius: 18)
        .tint(Theme.accent)
        .accentColor(Theme.accent)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MenuBarContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Native segmented selection, matching the close-behavior control in ToolsView.
private struct MenuBarPresetPicker: View {
    @ToolboxActions var state

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("预设模式").font(.callout).foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                PresetSegmentedControl(
                    presets: state.presetConfiguration.menuBarPresets,
                    selectedID: state.isConnected && !state.presetConfiguration.applicationIncomplete
                        ? (state.activePresetID ?? PicturePreset.baselineID) : nil,
                    isEnabled: state.isConnected && !state.isPresetOperationInFlight,
                    baselineEnabled: state.activePresetID == nil || state.canRestoreBaseline,
                    onSelect: { id in
                        guard id != (state.activePresetID ?? PicturePreset.baselineID)
                            || state.presetConfiguration.applicationIncomplete else { return }
                        if id == PicturePreset.baselineID { state.restoreBaseline() }
                        else { state.applyPreset(id: id) }
                    }
                )
                .accessibilityLabel("预设模式")
                .frame(width: MenuBarPanelLayout.presetWidth(count: state.presetConfiguration.menuBarPresets.count), height: 24)
            }
            .frame(height: 24)
            .disabled(!state.isConnected || state.isPresetOperationInFlight)
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
    let entry: MenuBarEntry

    /// 滑块拖动中的本地值：松手才下发，避免拖动过程刷出一串 ADB 命令
    @State private var dragging: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.kind {
            case .options(let options):
                Text(entry.label).font(.callout).foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { state.menuBarValue(for: entry.id) ?? -1 },
                    set: { state.applyMenuBarOption(entry.id, value: $0) }
                )) {
                    ForEach(options) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            case .stepper(let lo, let hi, _):
                let current = state.menuBarValue(for: entry.id) ?? lo
                HStack {
                    Text(entry.label).font(.callout).foregroundColor(.secondary)
                    Spacer()
                    Text("\(dragging ?? current)")
                        .font(.callout.monospacedDigit())
                        .foregroundColor(.primary)
                }
                // 用自绘的 FastSlider 而不是系统 Slider：
                // 后者底层是 NSSlider，每次创建都要向 CoreUI 解析主题 rendition，
                // 正是之前画面页切页卡 1.6 秒的根因（见 README 性能那节）。
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
            }
        }
        .disabled(!state.isConnected)
        .opacity(state.isConnected ? 1 : 0.5)
    }
}

// 注：曾经的菜单式渲染（MenuBarMenu / MenuBarEntryMenu）已删除 ——
// 改成 .window 样式的面板后它就没有调用方了。
