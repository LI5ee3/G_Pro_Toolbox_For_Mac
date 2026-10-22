import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct GameView: View {
    @ToolboxActions var state
    @Environment(PictureModel.self) private var picture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "游戏模式") { state.forceRefreshPage("game") }

                SectionCard(title: "刷新与同步") {
                    HStack(spacing: 24) {
                        gameOptionRow(title: "320Hz 竞技模式", options: OptionLists.mode320,
                                      followsGameMode: false,
                                      selectedValue: picture.intValue("mode_320", default: 0)) { v in
                            state.setMode320(v == 1)
                        }

                        Divider().overlay(Theme.stroke.opacity(0.6)).frame(height: 34)
                        gameOptionRow(title: "FreeSync Premium Pro", options: OptionLists.freesync,
                                      followsGameMode: false,
                                      selectedValue: picture.intValue("freesync", default: 0)) { v in
                            state.setFreesync(v == 1)
                        }
                    }
                }

                Label(picture.gameModeHintText,
                      systemImage: picture.gameModeHintIsWarning ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(picture.gameModeHintIsWarning ? Theme.warning : Theme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(picture.gameModeHintIsWarning ? Color.orange.opacity(0.08) : Theme.control,
                                in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 14) {
                    gameSectionHeading("瞄准辅助")
                    gameOptionRow(title: "准星", options: OptionLists.crosshair,
                                  selectedValue: picture.intValue("front_sight_index", default: 0)) { v in
                        state.setCrosshair(v)
                    }

                    gameOptionRow(title: "动态准星", options: OptionLists.dynamicCrosshair,
                                  selectedValue: picture.intValue("mt_game_dynamic_ft", default: 0)) { v in
                        state.setGameFeature(key: "mt_game_dynamic_ft", value: v,
                                             message: "动态准星: \(v == 0 ? "关" : "开")")
                    }

                    gameOptionRow(title: "狙击镜", options: OptionLists.scope,
                                  selectedValue: picture.intValue("mt_game_scope", default: 0)) { v in
                        state.setGameFeature(key: "mt_game_scope", value: v,
                                             message: "狙击镜: \(v == 0 ? "关" : "\(v)")")
                    }

                    gameOptionRow(title: "狙击镜夜视", options: OptionLists.scopeNight,
                                  selectedValue: picture.intValue("mt_game_scope_night", default: 0)) { v in
                        state.setGameFeature(key: "mt_game_scope_night", value: v,
                                             message: "狙击镜夜视: \(v == 0 ? "关" : "开")")
                    }
                }

                Divider().overlay(Theme.stroke.opacity(0.6))
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 14) {
                    gameSectionHeading("屏幕工具")
                    gameOptionRow(title: "FPS 计数器", options: OptionLists.fpsCounter,
                                  selectedValue: picture.intValue("monitor_menu_fps_counter", default: 0)) { v in
                        let name = v == 0 ? "关" : (v == 1 ? "刷新率" : "柱状图")
                        state.setGameFeature(key: "monitor_menu_fps_counter", value: v, message: "FPS: \(name)")
                    }

                    gameOptionRow(title: "秒表", options: OptionLists.stopwatch,
                                  selectedValue: picture.intValue("monitor_menu_stopwatch", default: 0)) { v in
                        state.setGameFeature(key: "monitor_menu_stopwatch", value: v,
                                             message: "秒表: \(v == 0 ? "关" : "开")")
                    }

                    gameOptionRow(title: "定时器", options: OptionLists.timer,
                                  selectedValue: picture.intValue("monitor_menu_timer", default: 0)) { v in
                        state.setGameFeature(key: "monitor_menu_timer", value: v, message: "定时器: \(v)")
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .font(.system(size: 14))
        }
        .onAppear { state.refreshPage("game") }
        .loadingOverlay(picture.loadingPages.contains("game"))
    }

    private func gameSectionHeading(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if picture.gameModeState != .active {
                Text(picture.gameModeState == .inactive ? "已记住 · 游戏模式生效" : "生效状态待确认")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func rememberedOption(_ option: Option, isSelected: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(option.label)
                .font(.callout)
                .frame(minWidth: 56)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundColor(Theme.secondaryText)
                .background(isSelected ? Theme.stroke.opacity(0.65) : Theme.control.opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Theme.secondaryText.opacity(0.45) : .clear))
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? (picture.gameModeState == .inactive ? "已记住，游戏模式生效" : "生效状态待确认") : "未选择")
    }

    private func gameOptionRow(title: String, options: [Option], followsGameMode: Bool = true,
                               selectedValue: Int,
                               onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 184, alignment: .leading)
            HStack(spacing: 7) {
                ForEach(options) { option in
                    if followsGameMode && picture.gameModeState != .active {
                        rememberedOption(option, isSelected: option.value == selectedValue) {
                            onSelect(option.value)
                        }
                    } else {
                        SelectableButton(title: option.label, isSelected: option.value == selectedValue) {
                            onSelect(option.value)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
