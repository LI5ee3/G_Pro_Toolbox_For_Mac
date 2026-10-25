import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct HomeView: View {
    @Environment(ToolboxSession.self) private var session
    @Environment(\.openSettings) private var openSettings
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PictureModel.self) private var picture
    @Environment(PresetsModel.self) private var presets
    @Environment(ToolsModel.self) private var tools
    @Environment(HotkeysModel.self) private var keyboard
    @Environment(NavigationModel.self) private var navigation
    @State private var backlight = 1.0

    private var source: String {
        guard connection.isConnected else { return "—" }
        guard let raw = picture.currentValues["mitv.tvplayer.hdmi.last.source"],
              let value = Int(raw), let name = RegisterMap.sourceNames[value] else { return "—" }
        return name == "DP" ? "DisplayPort" : name
    }
    private var backlightReading: Int? {
        connection.isConnected ? Int(picture.currentValues["picture_backlight"] ?? "") : nil
    }
    private var guardian: String {
        if !connection.isConnected { return "保活状态待连接" }
        return tools.guardianStatus.contains("✅") ? "保活正常" : "查看保活状态"
    }
    private var selectedMode: Int {
        guard connection.isConnected else { return -1 }
        return [14, 9, 10].first {
            RegisterMap.pictureModeGroupName(picture.intValue("picture_mode", default: -1)) == RegisterMap.modeNames[$0]
        } ?? -1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(connection.deviceDisplayName).font(.system(size: 24, weight: .semibold))
                            Text(connection.activeControlText).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        if !connection.isConnected {
                            Button("连接显示器…") { navigation.showsConnectionSettings = true }.toolboxAction(prominent: true)
                        }
                    }
                    if !connection.identityNotice.isEmpty {
                        Label(connection.identityNotice, systemImage: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 13)).foregroundStyle(Theme.warning)
                    }
                    SectionCard(title: "常用控制") {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 48) {
                                DashboardVolumeControl().frame(maxWidth: .infinity)
                                backlightControl.frame(maxWidth: .infinity)
                            }
                            .overlay {
                                Rectangle().fill(Theme.stroke).frame(width: 1)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 24) {
                                    Text("画面模式").font(Theme.sectionFont)
                                    SegmentedOptionPicker(options: [14, 9, 10].map {
                                        Option(label: RegisterMap.modeNames[$0] ?? "", value: $0)
                                    }, selectedValue: selectedMode, controlSize: .regular) { state.setMode($0) }
                                        .frame(width: 252)
                                        .disabled(!connection.isConnected)
                                        .accessibilityLabel("画面模式")
                                    Spacer(minLength: 0)
                                }
                                Text(connection.isConnected ? picture.pictureModeHint : "当前场景：未知（未连接）")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                VStack(spacing: 0) {
                    destination("视频输入", value: source, icon: "cable.connector", page: .source)
                        .disabled(!connection.isConnected)
                    Divider()
                    destination("预设", value: state.activePresetName, icon: "square.stack.3d.up", page: .presets)
                        .disabled(!connection.isConnected)
                    Divider()
                    destination("自动任务", value: presets.automaticTaskStatus.isEmpty ? "任务状态待更新" : presets.automaticTaskStatus,
                                icon: "calendar.badge.clock", page: .autoTasks)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button { state.requestedPage = .tools } label: { Label(guardian, systemImage: "checkmark.shield") }
                            .help(tools.guardianStatus)
                        Button { session.settingsPane = .keyboard; openSettings() } label: {
                            Label(keyboard.mediaVolumeKeysEnabled ? (keyboard.accessibilityTrusted ? "键盘音量控制已开启" : "键盘控制需要授权") : "键盘音量设置", systemImage: "keyboard")
                        }
                        Spacer()
                        Button("设备身份与归属…") { navigation.showsConnectionSettings = true }
                    }
                    .font(.system(size: 13)).buttonStyle(.bordered)
                    Text(connection.recoveryText).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(24).frame(maxWidth: 970).frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            syncBacklight()
            if connection.isConnected { state.refreshPage("picture"); state.refreshPage("source") }
        }
        .onChange(of: picture.currentValues["picture_backlight"]) { syncBacklight() }
    }

    private var backlightControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("背光", systemImage: "sun.max").font(Theme.sectionFont)
                Spacer()
                Text(backlightReading != nil ? String(Int(backlight)) : "—").font(.system(size: 28, weight: .medium)).monospacedDigit()
                Text("/ 100").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            FastSlider(value: $backlight, range: ControlRanges.backlight.sliderBounds, step: 1) { value in
                state.setPictureSlider(title: "背光", value: Int(value), jniKey: "g_disp__disp_back_light",
                                       settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
            }
            .accessibilityLabel("显示器背光")
            .accessibilityValue(backlightReading != nil ? String(Int(backlight)) : "未知")
            .disabled(!connection.isConnected || picture.currentValues["picture_backlight"] == nil)
            Button { state.requestedPage = .picture } label: {
                HStack(spacing: 4) {
                    Text("更多画面设置")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 24, alignment: .leading)
            .disabled(!connection.isConnected)
        }
    }

    private func destination(_ title: String, value: String, icon: String, page: Page) -> some View {
        Button { state.requestedPage = page } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: icon).frame(width: 20)
                    Text(title)
                }.font(.system(size: 14, weight: .medium)).frame(width: 105, alignment: .leading)
                Text(value).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }.padding(.vertical, 15).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func syncBacklight() { backlight = Double(picture.intValue("picture_backlight", default: 1)) }
}
