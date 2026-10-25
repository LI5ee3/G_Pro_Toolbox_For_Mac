import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct GameView: View {
    @ToolboxActions var state
    @Environment(PictureModel.self) private var picture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "游戏模式") { state.forceRefreshPage("game") }

                VStack(alignment: .leading, spacing: 8) {
                    Text("刷新与同步").font(Theme.sectionFont)
                    VStack(alignment: .leading, spacing: 4) {
                        gameOptionRow(title: "320Hz 竞技模式", options: OptionLists.mode320,
                                      followsGameMode: false,
                                      selectedValue: picture.intValue("mode_320", default: -1)) { v in
                            state.setMode320(v == 1)
                        }

                        gameOptionRow(title: "FreeSync Premium Pro", options: OptionLists.freesync,
                                      followsGameMode: false,
                                      selectedValue: picture.intValue("freesync", default: -1)) { v in
                            state.setFreesync(v == 1)
                        }
                    }
                }

                gameModeStatus

                VStack(alignment: .leading, spacing: 8) {
                    gameSectionHeading("瞄准辅助")
                    VStack(alignment: .leading, spacing: 4) {
                        gameOptionRow(title: "准星", options: OptionLists.crosshair,
                                      selectedValue: picture.intValue("front_sight_index", default: -1)) { v in
                            state.setCrosshair(v)
                        }

                        gameOptionRow(title: "动态准星", options: OptionLists.dynamicCrosshair,
                                      selectedValue: picture.intValue("mt_game_dynamic_ft", default: -1)) { v in
                            state.setGameFeature(key: "mt_game_dynamic_ft", value: v,
                                                 message: "动态准星: \(v == 0 ? "关" : "开")")
                        }

                        gameOptionRow(title: "狙击镜", options: OptionLists.scope,
                                      selectedValue: picture.intValue("mt_game_scope", default: -1)) { v in
                            state.setGameFeature(key: "mt_game_scope", value: v,
                                                 message: "狙击镜: \(v == 0 ? "关" : "\(v)")")
                        }

                        gameOptionRow(title: "狙击镜夜视", options: OptionLists.scopeNight,
                                      selectedValue: picture.intValue("mt_game_scope_night", default: -1)) { v in
                            state.setGameFeature(key: "mt_game_scope_night", value: v,
                                                 message: "狙击镜夜视: \(v == 0 ? "关" : "开")")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    gameSectionHeading("屏幕工具")
                    VStack(alignment: .leading, spacing: 4) {
                        gameOptionRow(title: "FPS 计数器", options: OptionLists.fpsCounter,
                                      selectedValue: picture.intValue("monitor_menu_fps_counter", default: -1)) { v in
                            let name = v == 0 ? "关" : (v == 1 ? "刷新率" : "柱状图")
                            state.setGameFeature(key: "monitor_menu_fps_counter", value: v, message: "FPS: \(name)")
                        }

                        gameOptionRow(title: "秒表", options: OptionLists.stopwatch,
                                      selectedValue: picture.intValue("monitor_menu_stopwatch", default: -1)) { v in
                            state.setGameFeature(key: "monitor_menu_stopwatch", value: v,
                                                 message: "秒表: \(v == 0 ? "关" : "开")")
                        }

                        gameOptionRow(title: "定时器", options: OptionLists.timer,
                                      selectedValue: picture.intValue("monitor_menu_timer", default: -1)) { v in
                            state.setGameFeature(key: "monitor_menu_timer", value: v, message: "定时器: \(v)")
                        }
                    }
                }
            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .font(Theme.bodyFont)
        }
        .onAppear { state.refreshPage("game") }
        .loadingOverlay(picture.loadingPages.contains("game"))
    }

    private var gameModeStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(gameModeStatusText,
                  systemImage: picture.gameModeHintIsWarning ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(picture.gameModeHintIsWarning ? Theme.warning : Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if picture.gameModeState == .inactive {
                Button("前往画面设置") { state.requestedPage = .picture }
                    .toolboxAction()
                    .fixedSize()
            }
        }
        .font(Theme.detailFont)
        .padding(picture.gameModeHintIsWarning ? 12 : 0)
        .background {
            if picture.gameModeHintIsWarning {
                RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.08))
            }
        }
    }

    private var gameModeStatusText: String {
        switch picture.gameModeState {
        case .active: return "当前为游戏模式，瞄准辅助与屏幕工具显示当前生效值。"
        case .inactive: return "当前不是游戏模式，瞄准辅助与屏幕工具暂未生效，仍可调整记忆值。"
        case .unknown: return "当前画面模式未知，瞄准辅助与屏幕工具是否生效待确认，仍可调整。"
        }
    }

    private func gameSectionHeading(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Theme.sectionFont)
            if picture.gameModeState != .active {
                Text(picture.gameModeState == .inactive ? "记忆值" : "待确认")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func gameOptionRow(title: String, options: [Option], followsGameMode: Bool = true,
                               selectedValue: Int,
                               onSelect: @escaping (Int) -> Void) -> some View {
        ParameterPickerRow(title: title, options: options, selectedValue: selectedValue,
                           onSelect: onSelect, labelWidth: 160)
            .accessibilityHint(followsGameMode && picture.gameModeState != .active
                ? (picture.gameModeState == .inactive ? "记忆值，游戏模式生效后启用；仍可调整" : "生效状态待确认；仍可调整") : "")
    }
}
