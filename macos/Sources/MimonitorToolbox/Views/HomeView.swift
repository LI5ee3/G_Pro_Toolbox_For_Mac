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
    @State private var showsNewPreset = false

    private var selectedSource: Int {
        connection.isConnected ? picture.intValue("mitv.tvplayer.hdmi.last.source", default: -1) : -1
    }
    private var source: String {
        guard let name = RegisterMap.sourceNames[selectedSource] else { return "未知" }
        return name == "DP" ? "DisplayPort" : name
    }
    private var backlightReading: Int? {
        guard connection.isConnected, let value = Int(picture.currentValues["picture_backlight"] ?? ""),
              ControlRanges.backlight.contains(value) else { return nil }
        return value
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
                deviceHeader
                GroupBox {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 28) {
                            DashboardVolumeControl().frame(maxWidth: .infinity)
                            Divider()
                            backlightControl.frame(maxWidth: .infinity)
                        }.fixedSize(horizontal: false, vertical: true)
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 20) {
                                Text("画面模式").font(Theme.sectionFont)
                                GlassEffectContainer(spacing: 8) {
                                    HStack(spacing: 8) {
                                        ForEach([14, 9, 10], id: \.self) { mode in
                                            Button { state.setMode(mode) } label: {
                                                Text(RegisterMap.modeNames[mode] ?? "")
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .font(Theme.controlFont).controlSize(.large)
                                            .buttonBorderShape(.capsule)
                                            .modifier(ToolboxSelectionButtonSurface(selected: selectedMode == mode))
                                            .accessibilityValue(selectedMode == mode ? "当前模式" : "未选中")
                                            .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                                        }
                                    }
                                }
                                    .frame(width: 252)
                                    .accessibilityElement(children: .contain).accessibilityLabel("画面模式")
                                    .disabled(!connection.isConnected || presets.presetConfiguration.applicationIncomplete)
                                Spacer(minLength: 0)
                            }
                            Text(connection.isConnected ? picture.pictureModeHint : "当前场景：未知（未连接）")
                                .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                        }
                    }.padding(16)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("视频输入").font(Theme.sectionFont)
                        Spacer()
                        Text("当前为 \(source)").font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                    }
                    VideoInputPicker(selectedValue: selectedSource) { state.setSource($0) }
                        .disabled(!connection.isConnected)
                }
                presetRow
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button { session.settingsPane = .keyboard; openSettings() } label: {
                            Label(keyboard.mediaVolumeKeysEnabled ? (keyboard.accessibilityTrusted ? "键盘音量控制已开启" : "键盘控制需要授权") : "键盘音量设置", systemImage: "keyboard")
                        }.toolboxAction()
                        Spacer()
                        Button { state.requestedPage = .tools } label: {
                            Label(guardian, systemImage: "checkmark.shield")
                        }.toolboxAction().help(tools.guardianStatus)
                    }
                    if !connection.recoveryText.isEmpty {
                        Text(connection.recoveryText).font(Theme.captionFont).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(28).frame(maxWidth: 970).frame(maxWidth: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showsNewPreset) {
            PresetNameSheet(preset: nil) { state.createPreset(name: $0) }
        }
        .onAppear {
            syncBacklight()
            if connection.isConnected { state.refreshPage("picture"); state.refreshPage("source") }
        }
        .onChange(of: picture.currentValues["picture_backlight"]) { syncBacklight() }
    }

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(systemName: "display")
                    .font(.system(size: 38, weight: .light)).foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(connection.deviceDisplayName).font(Theme.deviceTitle)
                    HStack(spacing: 10) {
                        Label(connection.statusTitle, systemImage: connection.statusSymbol)
                            .foregroundStyle(connection.statusColor).help(connection.statusText)
                        Text(connection.activeControlText).foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }.font(Theme.detailFont)
                }
                Spacer(minLength: 8)
                if !connection.isConnected {
                    Button("连接显示器…") { navigation.showsConnectionSettings = true }.toolboxAction(prominent: true)
                }
            }
            if !connection.identityNotice.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(connection.identityNotice, systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("确认归属…") { navigation.showsConnectionSettings = true }.toolboxAction().fixedSize()
                }.font(Theme.detailFont)
            }
        }
    }

    private var presetRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 21)).foregroundStyle(Theme.accent)
                .frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.activePresetName).font(Theme.sectionFont)
                Text(presets.presetConfiguration.applicationIncomplete ? "应用未完成，自动保存已暂停" : state.activePresetID == nil ? "调整仅作用于当前显示器" : "画面调整自动保存到此预设")
                    .font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("管理预设") { state.requestedPage = .presets }.toolboxAction()
            Button { showsNewPreset = true } label: { Label("新建预设", systemImage: "plus") }
                .toolboxAction().disabled(!connection.isConnected || presets.presetConfiguration.applicationIncomplete)
        }.padding(.vertical, 20)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
    }

    private var backlightControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("背光", systemImage: "sun.max").font(Theme.sectionFont)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(backlightReading != nil ? String(Int(backlight)) : "—")
                    .font(Theme.readingFont).monospacedDigit()
                Text("/ 100").font(Theme.detailFont).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("画面设置") { state.requestedPage = .picture }
                    .toolboxAction().disabled(!connection.isConnected)
            }
            FastSlider(value: $backlight, range: ControlRanges.backlight.sliderBounds, step: 1) { value in
                state.setPictureSlider(title: "背光", value: Int(value), jniKey: "g_disp__disp_back_light",
                                       settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
            }
            .accessibilityLabel("显示器背光")
            .accessibilityValue(backlightReading != nil ? String(Int(backlight)) : "未知")
            .disabled(backlightReading == nil || presets.presetConfiguration.applicationIncomplete)
        }
    }

    private func syncBacklight() { backlight = Double(picture.intValue("picture_backlight", default: 1)) }
}
