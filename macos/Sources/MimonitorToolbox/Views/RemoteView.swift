import SwiftUI

struct RemoteView: View {
    @ToolboxActions var state

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Text("遥控器").font(.system(size: 23, weight: .semibold))
                    Spacer()
                }

                VStack(spacing: 24) {
                    HStack {
                        Spacer()
                        Button {
                            state.key("KEYCODE_POWER")
                        } label: {
                            Image(systemName: "power")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(.red)
                                .frame(width: 28, height: 28)
                        }
                        .toolboxAction()
                        .accessibilityLabel("显示器电源")
                        .help("切换显示器电源状态")
                    }

                    HStack(spacing: 10) {
                        remoteButton("主页", symbol: "house", key: "KEYCODE_HOME")
                        remoteButton("菜单", symbol: "line.3.horizontal", key: "KEYCODE_MENU")
                        remoteButton("返回", symbol: "arrow.uturn.backward", key: "KEYCODE_BACK")
                    }

                    VStack(spacing: 6) {
                        dpadButton("向上", symbol: "chevron.up", key: "KEYCODE_DPAD_UP")
                        HStack(spacing: 6) {
                            dpadButton("向左", symbol: "chevron.left", key: "KEYCODE_DPAD_LEFT")
                            Button {
                                state.key("KEYCODE_DPAD_CENTER")
                            } label: {
                                Text("OK")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .frame(width: 52, height: 52)
                            }
                            .foregroundStyle(Theme.onAccent)
                            .background(Theme.accent, in: Circle())
                            .buttonStyle(ControlPressStyle())
                            .accessibilityLabel("确认")
                            .help("确认当前选择")
                            dpadButton("向右", symbol: "chevron.right", key: "KEYCODE_DPAD_RIGHT")
                        }
                        dpadButton("向下", symbol: "chevron.down", key: "KEYCODE_DPAD_DOWN")
                    }
                    .frame(width: 226, height: 218)
                    .background(Circle().fill(Theme.control))
                    .overlay(Circle().stroke(Theme.stroke))

                    HStack(spacing: 10) {
                        remoteButton("音量－", symbol: "speaker.wave.1", key: "KEYCODE_VOLUME_DOWN")
                        remoteButton("静音", symbol: "speaker.slash", key: "KEYCODE_VOLUME_MUTE")
                        remoteButton("音量＋", symbol: "speaker.wave.3", key: "KEYCODE_VOLUME_UP")
                    }
                }
                .padding(24)
                .frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Theme.stroke))
                .shadow(color: .black.opacity(0.04), radius: 16, y: 8)
                .padding(.bottom, 8)
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
    }

    private func remoteButton(_ title: String, symbol: String, key: String) -> some View {
        Button {
            state.key(key)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
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
                .foregroundColor(Theme.secondaryText)
                .frame(width: 28, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .toolboxAction()
        .accessibilityLabel(title)
        .help(title)
    }
}
