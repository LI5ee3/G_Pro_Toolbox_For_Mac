import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct LightView: View {
    @ToolboxActions var state
    @Environment(PictureModel.self) private var picture

    private var lightMode: Int { picture.intValue("atmosphere_light_switcher_pm2", default: -1) }
    private var modeIsKnown: Bool { OptionLists.lightMode.contains { $0.value == lightMode } }
    private var brightnessApplies: Bool { lightMode == 0 || lightMode == 2 }
    private var illumination: Int {
        let raw = picture.intValue("atmosphere_light_illumination", default: -1)
        return ControlRanges.screenLightDevice.contains(raw) ? raw + 1 : -1
    }
    private var colorTemperature: Int { picture.intValue("atmosphere_light_color_temp", default: -1) }
    private var solidColor: Int { picture.intValue("atmosphere_light_color_value", default: -1) }

    private var brightnessHint: String {
        guard modeIsKnown else { return "模式未知，亮度生效待确认。" }
        if !brightnessApplies {
            let status = illumination == -1 ? "读数未知" : "记忆值"
            return "\(status) · 照明或纯色模式下生效"
        }
        return illumination == -1 ? "亮度未知，生效待确认。" : "当前生效"
    }

    private func colorHint(mode: Int, name: String, value: Int, options: [Option]) -> String {
        let status: String
        if !modeIsKnown { status = "生效待确认" }
        else if !options.contains(where: { $0.value == value }) { status = "读数未知" }
        else { status = lightMode == mode ? "当前生效" : "记忆值" }
        return lightMode == mode ? status : "\(status) · 更改会切至\(name)模式"
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer { VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "屏幕灯") { state.forceRefreshPage("light") }

                VStack(alignment: .leading, spacing: 8) {
                    Text("模式与亮度").font(Theme.sectionFont)
                    VStack(alignment: .leading, spacing: 4) {
                        ParameterPickerRow(title: "炫彩灯模式", options: OptionLists.lightMode,
                                           selectedValue: lightMode) { state.setLightMode($0) }
                        VStack(alignment: .leading, spacing: 4) {
                            // Firmware 0...14 is shown as 1...15; the existing action converts on commit.
                            SliderRow(title: "亮度挡位", range: ControlRanges.screenLightUI.sliderBounds,
                                      externalValue: illumination) { state.setLightIllumination($0) }
                            parameterHint(brightnessHint)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("灯光颜色").font(Theme.sectionFont)
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            let hint = colorHint(mode: 0, name: "照明", value: colorTemperature,
                                                 options: OptionLists.lightColorTemp)
                            ParameterPickerRow(title: "照明色温", options: OptionLists.lightColorTemp,
                                               selectedValue: colorTemperature) {
                                state.setLightColorTemp($0)
                            }
                            .accessibilityHint(hint)
                            parameterHint(hint)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            let hint = colorHint(mode: 2, name: "纯色", value: solidColor,
                                                 options: OptionLists.lightColor)
                            ParameterPickerRow(title: "纯色颜色", options: OptionLists.lightColor,
                                               selectedValue: solidColor) {
                                state.setLightColor($0)
                            }
                            .accessibilityHint(hint)
                            parameterHint(hint)
                        }
                    }
                }
            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24).font(Theme.bodyFont)
            }
        }
        .onAppear { state.refreshPage("light") }
    }

    private func parameterHint(_ text: String) -> some View {
        Text(text)
            .font(Theme.detailFont)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, Theme.parameterLabelWidth + 12)
    }
}
