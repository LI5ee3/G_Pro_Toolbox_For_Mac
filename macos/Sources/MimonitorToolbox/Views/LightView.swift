import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct LightView: View {
    @ToolboxActions var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lightMode: Int {
        state.intValue("atmosphere_light_switcher_pm2", default: 4)
    }

    // The LED helper accepts brightness only for lighting and solid modes.
    private var brightnessApplies: Bool { lightMode == 0 || lightMode == 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "屏幕灯") { state.forceRefreshPage("light") }

                HStack(spacing: 14) {
                    Image(systemName: lightMode == 4 ? "lightbulb.slash" : "lightbulb")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(Theme.accent)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Theme.accent.opacity(0.08)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("炫彩灯模式")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                        Text(OptionLists.lightMode.first(where: { $0.value == lightMode })?.label ?? "未知")
                            .font(.system(size: 21, weight: .semibold))
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(OptionLists.lightMode) { option in
                        modeButton(option)
                    }
                }

                HStack(spacing: 10) {
                    Text("灯光调节").font(.system(size: 15, weight: .semibold))
                    if !brightnessApplies {
                        Text(lightMode == 4 ? "开启后生效" : "亮度在照明或纯色模式生效")
                            .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                    }
                }

                // 存储值为 0...14，界面显示 1...15；提交仍交给原状态方法转换。
                SliderRow(title: "亮度挡位", range: 1...15,
                          externalValue: state.intValue("atmosphere_light_illumination", default: 9) + 1) { v in
                    state.setLightIllumination(v)
                }
                .saturation(brightnessApplies ? 1 : 0)
                .opacity(brightnessApplies ? 1 : 0.65)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Text("灯光颜色").font(.system(size: 15, weight: .semibold))
                        if lightMode == 4 {
                            Text("开启后生效").font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                        }
                    }
                    lightOptionRow(title: "照明色温", options: OptionLists.lightColorTemp,
                                   isActive: lightMode == 0, modeName: "照明",
                                   selectedValue: state.intValue("atmosphere_light_color_temp", default: 1)) { v in
                        state.setLightColorTemp(v)
                    }

                    lightOptionRow(title: "纯色颜色", options: OptionLists.lightColor,
                                   isActive: lightMode == 2, modeName: "纯色",
                                   selectedValue: state.intValue("atmosphere_light_color_value", default: 0)) { v in
                        state.setLightColor(v)
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .font(.system(size: 14))
        }
        .onAppear { state.refreshPage("light") }
    }

    private func lightOptionRow(title: String, options: [Option], isActive: Bool, modeName: String,
                                selectedValue: Int,
                                onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !isActive {
                    Text("选择即切换到\(modeName)")
                        .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                }
            }
            .foregroundColor(isActive ? .primary : Theme.secondaryText)
            .frame(width: 160, alignment: .leading)
            HStack(spacing: 7) {
                ForEach(options) { option in
                    SelectableButton(title: option.label, isSelected: option.value == selectedValue) {
                        onSelect(option.value)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .saturation(isActive ? 1 : 0)
            .opacity(isActive ? 1 : 0.65)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func modeButton(_ option: Option) -> some View {
        let selected = option.value == lightMode
        return Button {
            state.setLightMode(option.value)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: modeSymbol(option.value))
                    .font(.system(size: 19, weight: .regular))
                Text(option.label)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(selected ? Theme.accent : Theme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(RoundedRectangle(cornerRadius: 11).fill(selected ? Theme.accent.opacity(0.09) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Theme.accent.opacity(0.5) : Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(option.label)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .help("将炫彩灯设为\(option.label)")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selected)
    }

    private func modeSymbol(_ mode: Int) -> String {
        switch mode {
        case 4: return "power"
        case 0: return "lightbulb"
        case 2: return "circle.fill"
        case 1: return "display"
        default: return "sparkles"
        }
    }
}
