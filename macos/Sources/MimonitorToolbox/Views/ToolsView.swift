import ToolboxDomain
import ToolboxApplication
import SwiftUI
import UniformTypeIdentifiers

struct ToolsView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(ToolsModel.self) private var tools
    @Environment(SettingsModel.self) private var settings
    @State private var pending4K = false
    @State private var show4KConfirm = false
    @State private var showAdvancedTools = false
    @State private var showGuardianConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("显示器工具").font(.system(size: 22, weight: .semibold))
                }
                memorySettings
                Divider()
                guardianSettings
                Divider()
                SettingsTaskSection(title: "高级工具") {
                    DisclosureGroup(isExpanded: $showAdvancedTools) {
                        VStack(alignment: .leading, spacing: 20) {
                            displayResolutionSettings
                            Divider()
                            installationTools
                            Divider()
                            terminalTools
                        }
                        .padding(.top, 16)
                    } label: {
                        Label("显示器系统、应用安装与 ADB 调试", systemImage: "wrench.and.screwdriver")
                    }
                    .tint(Theme.accent)
                    Text("4K UI 会重启显示器；安装与部署会修改显示器系统。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Button("项目源代码") { state.openProjectSource() }
                    Spacer()
                    Button("原项目") { state.openProjectSource(upstream: true) }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .font(.system(size: 14))
        .tint(Theme.accent)
        .onAppear { state.check4KState() }
        .alert("切换 4K UI 会重启显示器，继续？", isPresented: $show4KConfirm) {
            Button("取消", role: .cancel) { }
            Button("确认并重启") { state.toggle4K(pending4K) }
        } message: {
            Text(pending4K
                 ? "将设置 wm size 3840x2160 / density 640 并重启显示器。"
                 : "将恢复 wm size 1920x1080 / density 320 并重启显示器。")
        }
        .alert("部署或修复 AdbGuardian？", isPresented: $showGuardianConfirm) {
            Button("取消", role: .cancel) { }
            Button("部署或修复") { state.deployGuardian() }
        } message: {
            Text("将安装项目自带 APK，授予修改调试设置和无障碍权限，并开启网络 ADB 5555。完成后会回读实际状态。")
        }

    }

    private var guardianSettings: some View {
        SettingsTaskSection(title: "连接保活") {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 38)
                VStack(alignment: .leading, spacing: 8) {
                    Text(tools.guardianStatus).textSelection(.enabled)
                    Text("显示器端 AdbGuardian 尝试在重启、待机或唤醒后恢复 ADB。深度待机时服务可能停止，恢复时间由显示器系统决定。")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
            HStack(spacing: 10) {
                Button("检测状态") { state.checkGuardian() }
                    .toolboxAction()
                Button("启动保活") { state.startGuardian() }
                    .toolboxAction()
                Spacer()
                Button("部署或修复…") { showGuardianConfirm = true }
                    .toolboxAction()
            }
            Text("部署会安装自带 APK，授予修改调试设置和无障碍权限，并开启网络 ADB 5555。恢复效果需以实际待机和重启测试为准。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var memorySettings: some View {
        SettingsTaskSection(title: "自动记忆与联动") {
            settingToggle("分别记忆 HDR / SDR 精密控光", isOn: Binding(
                get: { state.effectiveHdrMemoryEnabled },
                set: { state.toggleHdrMemory($0) }
            ), disabled: state.memoriesSuspendedByPreset)
            Text(tools.hdrMemoryStatusText.isEmpty ? "状态待确认" : tools.hdrMemoryStatusText).foregroundStyle(Theme.secondaryText)
            Text("根据 macOS EDR 判断 HDR 信号。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            Divider().padding(.vertical, 2)
            settingToggle("关闭 FreeSync 后恢复原画面模式", isOn: Binding(
                get: { state.effectiveFreesyncMemoryEnabled },
                set: { state.toggleFreesyncMemory($0) }
            ), disabled: state.memoriesSuspendedByPreset)
            Text(tools.freesyncMemoryStatusText.isEmpty ? "状态待确认" : tools.freesyncMemoryStatusText).foregroundStyle(Theme.secondaryText)
            if state.memoriesSuspendedByPreset {
                Label(!connection.identityNotice.isEmpty ? connection.identityNotice : "使用预设时记忆设置已锁定；返回无预设后恢复。", systemImage: "lock")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            }
            Divider().padding(.vertical, 2)
            settingToggle("准星仅在游戏模式下生效", isOn: Binding(
                get: { tools.crosshairGameModeOnly },
                set: { state.toggleCrosshairGameModeOnly($0) }
            ), disabled: state.memoriesSuspendedByPreset)
            Text(tools.crosshairModeStatusText.isEmpty ? "状态待确认" : tools.crosshairModeStatusText).foregroundStyle(Theme.secondaryText)
        }
    }

    private var displayResolutionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("显示器 4K UI").font(Theme.sectionFont)
                Spacer()
                Button("重新检测") { state.check4KState() }
                    .toolboxAction()
            }
            Text(tools.fourKReadFailure == nil
                 ? "当前：\(tools.is4KUI ? "4K · 3840×2160 / DPI 640" : "1080p · 1920×1080 / DPI 320")"
                 : "当前：未知（读取失败，请重新检测）")
                .foregroundStyle(Theme.secondaryText)
            settingToggle("启用 4K UI", isOn: Binding(
                get: { tools.is4KUI },
                set: { pending4K = $0; show4KConfirm = true }
            ), disabled: tools.fourKReadFailure != nil)
            Text("仅改变显示器内置系统界面的分辨率。切换前会再次确认，确认后显示器将重启。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
        }
    }

    private var installationTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("安装显示器应用").font(Theme.sectionFont)
            Text("选择本地 APK，使用 adb install -r -d 安装到显示器。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                Button("选择 APK 并安装…") { state.chooseAPK() }
                    .toolboxAction()
                if connection.isConnected {
                    Label("已连接", systemImage: "checkmark.circle").foregroundStyle(Theme.success)
                }
            }
        }
    }

    // Keep the name readable while only the native control adopts its disabled appearance.
    private func settingToggle(_ title: String, isOn: Binding<Bool>, disabled: Bool) -> some View {
        LabeledContent(title) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.checkbox).disabled(disabled)
        }
    }

    private var terminalTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADB 命令行").font(Theme.sectionFont)
            Text("使用当前 ADB 端点打开终端。命令可直接修改显示器，请确认操作对象。")
                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                Button("打开 ADB 命令行") { state.openAdbCmd() }
                    .toolboxAction()
                Button("进入 ADB Shell") { state.openAdbShell() }
                    .toolboxAction()
            }
            if let result = settings.terminalResult, result.outcome != .opened {
                Text(result.outcome == .denied ? "上次 Terminal 请求被拒绝，请在系统设置中允许后重试。" : "Terminal 未确认完成，请检查日志后重试。")
                    .font(.system(size: 13)).foregroundStyle(Theme.warning)
            }
            Button("自动化权限设置") { state.openAutomationSettings() }.toolboxAction()
        }
    }
}

// MARK: - 快捷键配置面板

/// 独立的配置 sheet。放在 sheet 里而不是内联折叠，是因为内联展开会改变整页高度、
/// 触发工具页所有卡片的重新布局（实测 850ms）。
struct HotkeyConfigSheet: View {
    @ToolboxActions var state
    @Environment(HotkeysModel.self) private var keyboard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("键盘控制").font(.system(size: 22, weight: .semibold))
                    Text("录入组合键，或直接接管系统音量与亮度键。")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsTaskSection(title: "组合快捷键") {
                        ForEach(hotkeyActions, id: \.id) { action in
                            HotkeyRow(label: action.label, config: hotkeyBinding(action.id))
                        }

                        Divider().padding(.vertical, 4)

                        ForEach(keyboard.adjustHotkeys.indices, id: \.self) { i in
                            AdjustHotkeyRow(config: adjustBinding(i)) {
                                keyboard.adjustHotkeys.remove(at: i)
                            }
                        }
                        Button("新建可调快捷键") {
                            keyboard.adjustHotkeys.append(AdjustHotkeyConfig())
                        }
                        .toolboxAction()

                    }

                    Divider()

                    SettingsTaskSection(title: "亮度键") {
                        // 系统亮度调节键直接接管为显示器背光。
                        // 这类键可能以 NX_SYSDEFINED 或普通 keyDown(144/145) 到达，都要拦。
                        HStack(spacing: 12) {
                            Toggle("亮度调节键调显示器背光", isOn: Binding(get: { keyboard.mediaBrightnessKeysEnabled }, set: { state.mediaBrightnessKeysEnabled = $0 }))
                                .toggleStyle(.checkbox)
                            // 开原生 OSD 时步长固定 16 格，整个隐藏，别留一个灰着的「步长 10」
                            if !keyboard.mediaBrightnessNativeOSD {
                                Stepper("步长 \(keyboard.mediaBrightnessStep)", value: Binding(get: { keyboard.mediaBrightnessStep }, set: { state.mediaBrightnessStep = $0 }), in: 1...100)
                                    .frame(width: 140)
                                    .disabled(!keyboard.mediaBrightnessKeysEnabled)
                            }
                            Spacer()
                        }
                        Text("调暗、调亮键控制此显示器背光，不再调节内置屏幕。需要辅助功能权限及 ADB 连接。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)

                        Toggle("使用 macOS 原生亮度提示（OSD）", isOn: Binding(get: { keyboard.mediaBrightnessNativeOSD }, set: { state.mediaBrightnessNativeOSD = $0 }))
                            .toggleStyle(.checkbox)
                            .disabled(!keyboard.mediaBrightnessKeysEnabled)
                        Text(keyboard.mediaBrightnessNativeOSD
                             ? "原生提示固定为 16 格，每按一次调节一格，步长不可调。"
                             : "当前使用应用悬浮提示，可自行设定调节步长。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)

                        Toggle("多屏时仅在鼠标位于「\(keyboard.mediaBrightnessDisplayName)」时拦截", isOn: Binding(get: { keyboard.mediaBrightnessFocusOnly }, set: { state.mediaBrightnessFocusOnly = $0 }))
                            .toggleStyle(.checkbox)
                            .disabled(!keyboard.mediaBrightnessKeysEnabled)
                        HStack(spacing: 8) {
                            Text("显示器名称")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                            TextField("Mi Monitor", text: Binding(get: { keyboard.mediaBrightnessDisplayName }, set: { state.mediaBrightnessDisplayName = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Spacer()
                        }
                        .disabled(!keyboard.mediaBrightnessKeysEnabled)
                        Text("鼠标不在目标显示器上时，亮度键交回系统处理（去调内置屏亮度）。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)

                    }

                    Divider()

                    SettingsTaskSection(title: "音量键") {
                        // 系统音量调节键接管为显示器音量。
                        HStack(spacing: 12) {
                            Toggle("音量调节键调显示器音量", isOn: Binding(get: { keyboard.mediaVolumeKeysEnabled }, set: { state.mediaVolumeKeysEnabled = $0 }))
                                .toggleStyle(.checkbox)
                            if !keyboard.mediaVolumeNativeOSD {
                                Stepper("步长 \(keyboard.mediaVolumeStep)", value: Binding(get: { keyboard.mediaVolumeStep }, set: { state.mediaVolumeStep = $0 }), in: 1...100)
                                    .frame(width: 140)
                                    .disabled(!keyboard.mediaVolumeKeysEnabled)
                            }
                            Spacer()
                        }
                        Text("音量加减、静音键通过当前已连接的 USB/TCP ADB 会话控制此显示器。需要辅助功能权限。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)

                        Toggle("使用 macOS 原生音量提示（OSD）", isOn: Binding(get: { keyboard.mediaVolumeNativeOSD }, set: { state.mediaVolumeNativeOSD = $0 }))
                            .toggleStyle(.checkbox)
                            .disabled(!keyboard.mediaVolumeKeysEnabled)
                        Text(keyboard.mediaVolumeNativeOSD
                             ? "原生音量提示固定为 16 格；提示失败时自动使用应用悬浮提示。"
                             : "当前使用应用悬浮提示，可自行设定调节步长。")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)

                        Toggle("仅当默认音频输出为指定设备时接管", isOn: Binding(get: { keyboard.mediaVolumeOutputGateEnabled }, set: { state.mediaVolumeOutputGateEnabled = $0 }))
                            .toggleStyle(.checkbox)
                            .disabled(!keyboard.mediaVolumeKeysEnabled)
                        HStack(spacing: 8) {
                            Text("音频输出设备名")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                            TextField("Mi Monitor", text: Binding(get: { keyboard.mediaVolumeOutputName }, set: { state.mediaVolumeOutputName = $0 }))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                            Spacer()
                        }
                        .disabled(!keyboard.mediaVolumeKeysEnabled || !keyboard.mediaVolumeOutputGateEnabled)
                    }
                }
                .padding(24)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("点「未设置」后直接按组合键即可录入")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)

                HStack(spacing: 12) {
                    // 排查"配了没反应"时才有用；平时开着手打键盘会把日志刷满
                    Toggle("诊断日志", isOn: Binding(
                        get: { keyboard.hotkeyDebugEnabled },
                        set: { state.hotkeyDebugEnabled = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                    .help("记录「按键码命中但修饰键不符」这类信息，用于排查快捷键不生效")

                    Spacer()
                    Button("完成") {
                        state.saveHotkeys()
                        dismiss()
                    }
                    .toolboxAction(prominent: true)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 760, idealWidth: 800, maxWidth: 940, minHeight: 620, idealHeight: 760, maxHeight: 900)
        .font(.system(size: 14))
        .tint(Theme.accent)
        .background(Theme.canvas)
    }

    private func hotkeyBinding(_ action: String) -> Binding<HotkeyConfig> {
        Binding(
            get: { keyboard.hotkeys[action] ?? HotkeyConfig() },
            set: { keyboard.hotkeys[action] = $0 }
        )
    }

    private func adjustBinding(_ index: Int) -> Binding<AdjustHotkeyConfig> {
        Binding(
            get: { index < keyboard.adjustHotkeys.count ? keyboard.adjustHotkeys[index] : AdjustHotkeyConfig() },
            set: { if index < keyboard.adjustHotkeys.count { keyboard.adjustHotkeys[index] = $0 } }
        )
    }
}

// MARK: - 按键录入

/// 快捷键录入按钮：点一下开始录制，然后直接按想用的组合键。
/// **修饰键和主键一起录** —— 按 Cmd+Option+Z 就同时记下两者。
///
/// 之前是「修饰键下拉 + 55 项按键下拉」两个 Picker。展开配置面板时，
/// 9 行就是 9 个 NSPopUpButton（每个 11 项）+ 55 项的长列表，
/// 实测要 1 秒才画完。改成单个录入按钮后一个 Picker 都不剩。
/// Esc 取消；不带修饰键的普通字母/数字会被拒绝（否则会劫持全局打字）。
struct KeyRecorderButton: View {
    @Binding var modifier: String
    @Binding var key: String
    var width: CGFloat = 150
    var title = "快捷键"

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? "请按键…" : displayText)
                    .frame(width: width)
            }
            .toolboxAction()
            .tint(recording ? .accentColor : nil)
            .accessibilityLabel("录制\(title)")
            .accessibilityValue(recording ? "录制中，按 Escape 取消" : displayText)

            if let hint {
                Text(hint).font(.system(size: 13)).foregroundStyle(Theme.warning)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var displayText: String {
        guard modifier != "无", key != "无" else { return "未设置" }
        return "\(modifier) + \(key)"
    }

    private func startRecording() {
        recording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc 取消
            if event.keyCode == 53 { stopRecording(); return nil }
            guard let name = HotkeyMap.keyName(for: event.keyCode) else {
                hint = "不支持的按键"
                return nil
            }
            let modName = HotkeyMap.modifierName(for: event.modifierFlags)
            // 没修饰键的字母/数字会被全局劫持，导致正常打字失灵，必须挡住
            let isFunctionKey = name.hasPrefix("F") && Int(name.dropFirst()) != nil
            if modName == "无" && !isFunctionKey {
                hint = "需要配合修饰键"
                return nil
            }
            modifier = modName
            key = name
            stopRecording()
            return nil   // 录制期间吞掉全部按键，避免误触发
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - 快捷键行

struct HotkeyRow: View {
    let label: String
    @Binding var config: HotkeyConfig

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 150, alignment: .leading)
            KeyRecorderButton(modifier: $config.modifier, key: $config.key, title: label)
            Spacer()
        }
    }
}

struct AdjustHotkeyRow: View {
    @Binding var config: AdjustHotkeyConfig
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("调整参数", selection: $config.param) {
                ForEach(adjustableParams, id: \.id) { Text($0.label).tag($0.id) }
            }
            .labelsHidden().frame(width: 100)
            Picker("调整方向", selection: $config.direction) {
                Text("增大").tag("increase")
                Text("减小").tag("decrease")
            }
            .labelsHidden().frame(width: 70)
            Stepper("步长 \(config.step)", value: $config.step, in: 1...100)
                .frame(width: 140)
            KeyRecorderButton(modifier: $config.modifier, key: $config.key, width: 130, title: "可调快捷键")
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .toolboxAction()
            .accessibilityLabel("删除可调快捷键")
        }
    }
}

/// Text-heavy settings stay on the page canvas; dividers separate tasks without nested cards.
private struct SettingsTaskSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Theme.sectionFont)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
