import ToolboxApplication
import SwiftUI

public enum ToolboxSettingsPane: String, CaseIterable, Identifiable {
    case general, keyboard, menuBar, connection, logs
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: "通用"
        case .keyboard: "键盘控制"
        case .menuBar: "菜单栏"
        case .connection: "连接"
        case .logs: "日志"
        }
    }
}

struct AppSettingsView: View {
    @Environment(ToolboxSession.self) private var session
    @Environment(ConnectionModel.self) private var connection

    var body: some View {
        @Bindable var session = session
        TabView(selection: $session.settingsPane) {
            Tab("通用", systemImage: "gearshape", value: .general) { GeneralSettingsView() }
            Tab("键盘控制", systemImage: "keyboard", value: .keyboard) { KeyboardSettingsView() }
            Tab("菜单栏", systemImage: "menubar.rectangle", value: .menuBar) { MenuBarSettingsView() }
            Tab("连接", systemImage: "cable.connector", value: .connection) { ConnectionSettingsView(connection: connection) }
            Tab("日志", systemImage: "text.alignleft", value: .logs) { OperationLogView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(Theme.accent)
        .accentColor(Theme.accent)
    }
}

/// Controls keep their existing model bindings; Form owns the macOS spacing and surfaces.
struct GeneralSettingsView: View {
    @ToolboxActions var state
    @Environment(SettingsModel.self) private var settings

    var body: some View {
        Form {
            Section("应用偏好") {
                LabeledContent("外观") {
                    SegmentedOptionPicker(options: [.init(label: "跟随系统", value: 0), .init(label: "深色", value: 1), .init(label: "浅色", value: 2)],
                                          selectedValue: ["auto": 0, "dark": 1, "light": 2][settings.theme] ?? -1) {
                        if let value = [0: "auto", 1: "dark", 2: "light"][$0] { settings.theme = value }
                    }
                    .frame(width: 300).accessibilityLabel("外观")
                }
                LabeledContent("关闭窗口时") {
                    SegmentedOptionPicker(options: [.init(label: "在菜单栏继续运行", value: 0), .init(label: "退出应用", value: 1)],
                                          selectedValue: ["tray": 0, "exit": 1][settings.closeBehavior] ?? -1) {
                        settings.closeBehavior = $0 == 1 ? "exit" : "tray"
                    }
                    .frame(width: 300).accessibilityLabel("关闭窗口时")
                }
            }
            Section {
                Toggle("登录后自动启动，仅显示菜单栏图标", isOn: Binding(
                    get: { settings.autostartEnabled }, set: { state.setAutostart($0) }
                ))
                .disabled(settings.loginItemBusy)
                LabeledContent {
                    HStack {
                        Button("登录项设置") { state.openLoginItemSettings() }
                            .toolboxAction()
                        Button("重新检测") { state.refreshLoginItem() }
                            .toolboxAction()
                    }
                    .disabled(settings.loginItemBusy)
                } label: {
                    Text(settings.loginItemBusy ? "正在读取系统登录项…" : settings.loginItem.detail)
                        .foregroundStyle(settings.loginItem.needsAttention ? Theme.warning : Theme.secondaryText)
                }
            } header: {
                Text("启动")
            }
            Section {
                LabeledContent("本地网络") {
                    Button("打开隐私设置") { state.openLocalNetworkSettings() }
                        .toolboxAction()
                        .help("系统设置 → 隐私与安全 → 本地网络")
                }
            } header: {
                Text("权限")
            } footer: {
                Text("打开后选择“本地网络”，检查本应用开关。连接失败也可能来自网络或设备，不能据此判断权限被拒绝。")
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardSettingsView: View {
    @ToolboxActions var state
    @Environment(HotkeysModel.self) private var keyboard
    @State private var showHotkeySheet = false

    private var configuredHotkeyCount: Int {
        keyboard.hotkeys.values.filter { $0.isEnabled }.count
            + keyboard.adjustHotkeys.filter { $0.isEnabled }.count
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("快捷键", value: "已配置 \(configuredHotkeyCount) 个")
                LabeledContent("组合键、系统音量键与亮度键") {
                    Button("配置快捷键…") { showHotkeySheet = true }
                        .toolboxAction()
                }
            } header: {
                Text("键盘控制")
            }
            Section {
                Label(keyboard.accessibilityTrusted ? "辅助功能权限已授予" : "尚未授权，键盘控制暂不生效",
                      systemImage: keyboard.accessibilityTrusted ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(keyboard.accessibilityTrusted ? Theme.success : Theme.warning)
                if !keyboard.accessibilityTrusted {
                    HStack {
                        Button("前往授权") { state.requestAccessibilityPermission() }
                            .toolboxAction()
                        Button("重新检测") { state.refreshAccessibilityStatus() }
                            .toolboxAction()
                    }
                }
                if keyboard.listenerStatus == .failed {
                    Text("辅助功能已允许，但监听尚未启动。请重新检测权限或重启应用。")
                        .foregroundStyle(Theme.warning)
                }
            } header: {
                Text("权限")
            } footer: {
                Text("授权后返回应用会自动重新检测。")
            }
            Section {
                Toggle("快捷键松手后生效", isOn: Binding(
                    get: { keyboard.hotkeyCountdownEnabled }, set: { state.hotkeyCountdownEnabled = $0 }
                ))
                LabeledContent("等待时长") {
                    FastSlider(value: Binding(
                        get: { keyboard.hotkeyCountdownSeconds }, set: { state.hotkeyCountdownSeconds = $0 }
                    ), range: 0.2...3.0, step: 0.1) { _ in }
                    .frame(width: 220)
                    .disabled(!keyboard.hotkeyCountdownEnabled)
                    .accessibilityLabel("快捷键等待时长")
                    .accessibilityValue(String(format: "%.1f 秒", keyboard.hotkeyCountdownSeconds))
                    Text(String(format: "%.1f 秒", keyboard.hotkeyCountdownSeconds)).monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            } header: {
                Text("提交方式")
            } footer: {
                Text(keyboard.hotkeyCountdownEnabled
                     ? "倒计时结束后提交，连续按键只保留最后一个值。"
                     : "每次按键立即提交；连续按键可能使 ADB 命令排队。")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showHotkeySheet) { HotkeyConfigSheet() }
    }
}
