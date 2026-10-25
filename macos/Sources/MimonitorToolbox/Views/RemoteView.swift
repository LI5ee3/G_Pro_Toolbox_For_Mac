import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct RemoteView: View {
    @ToolboxActions var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("遥控器").font(Theme.pageTitle)

                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("方向与确认").font(Theme.sectionFont)
                        VStack(spacing: 6) {
                            dpadButton("向上", symbol: "chevron.up", key: "KEYCODE_DPAD_UP")
                            HStack(spacing: 6) {
                                dpadButton("向左", symbol: "chevron.left", key: "KEYCODE_DPAD_LEFT")
                                Button { state.key("KEYCODE_DPAD_CENTER") } label: {
                                    Text("OK").font(.system(size: 16, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .focusEffectDisabled()
                                .tint(Theme.actionAccent)
                                .buttonBorderShape(.circle)
                                .controlSize(.large)
                                .frame(width: 52, height: 52)
                                .accessibilityLabel("确认")
                                .help("确认当前选择")
                                dpadButton("向右", symbol: "chevron.right", key: "KEYCODE_DPAD_RIGHT")
                            }
                            dpadButton("向下", symbol: "chevron.down", key: "KEYCODE_DPAD_DOWN")
                        }
                        .frame(width: 226, height: 218)
                        .background(Circle().fill(Theme.card))
                        .overlay(Circle().stroke(Theme.stroke))
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("导航").font(Theme.sectionFont)
                            HStack(spacing: 8) {
                                remoteButton("主页", symbol: "house", key: "KEYCODE_HOME")
                                remoteButton("菜单", symbol: "line.3.horizontal", key: "KEYCODE_MENU")
                                remoteButton("返回", symbol: "arrow.uturn.backward", key: "KEYCODE_BACK")
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("声音").font(Theme.sectionFont)
                            HStack(spacing: 8) {
                                remoteButton("音量－", symbol: "speaker.wave.1", key: "KEYCODE_VOLUME_DOWN")
                                remoteButton("静音", symbol: "speaker.slash", key: "KEYCODE_VOLUME_MUTE")
                                remoteButton("音量＋", symbol: "speaker.wave.3", key: "KEYCODE_VOLUME_UP")
                            }
                        }
                        Button { state.key("KEYCODE_POWER") } label: {
                            Label("电源", systemImage: "power")
                        }
                        .toolboxAction()
                        .accessibilityLabel("显示器电源")
                        .help("切换显示器电源状态")
                    }
                    .frame(maxWidth: 320)
                }
            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }

    private func remoteButton(_ title: String, symbol: String, key: String) -> some View {
        Button {
            state.key(key)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                Text(title).font(Theme.detailFont)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .toolboxAction()
        .accessibilityLabel(title)
        .help(title)
    }

    private func dpadButton(_ title: String, symbol: String, key: String) -> some View {
        Button {
            state.key(key)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .toolboxAction()
        .accessibilityLabel(title)
        .help(title)
    }
}
