import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct LightView: View {
    @ToolboxActions var state
    @Environment(PictureModel.self) private var picture

    private var lightMode: Int { picture.intValue("atmosphere_light_switcher_pm2", default: -1) }
    private var brightnessApplies: Bool { lightMode == 0 || lightMode == 2 }
    private var illumination: Int {
        let raw = picture.intValue("atmosphere_light_illumination", default: -1)
        return ControlRanges.screenLightDevice.contains(raw) ? raw + 1 : -1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "屏幕灯") { state.forceRefreshPage("light") }

                VStack(alignment: .leading, spacing: 8) {
                    Text("模式与亮度").font(Theme.sectionFont)
                    ParameterPickerRow(title: "炫彩灯模式", options: OptionLists.lightMode,
                                       selectedValue: lightMode) { state.setLightMode($0) }
                    // Firmware 0...14 is shown as 1...15; the existing action converts on commit.
                    SliderRow(title: "亮度挡位", range: ControlRanges.screenLightUI.sliderBounds,
                              externalValue: illumination) { state.setLightIllumination($0) }
                    if !brightnessApplies {
                        Text(lightMode == 4 ? "当前关闭；亮度保留为记忆值，在照明或纯色模式下生效。"
                             : "亮度仅在照明或纯色模式下生效，仍可调整记忆值。")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            .padding(.leading, Theme.parameterLabelWidth + 12)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("灯光颜色").font(Theme.sectionFont)
                    ParameterPickerRow(title: "照明色温", options: OptionLists.lightColorTemp,
                                       selectedValue: picture.intValue("atmosphere_light_color_temp", default: -1)) {
                        state.setLightColorTemp($0)
                    }
                    if lightMode != 0 {
                        Text("选择色温会切换到照明模式。")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            .padding(.leading, Theme.parameterLabelWidth + 12)
                    }
                    ParameterPickerRow(title: "纯色颜色", options: OptionLists.lightColor,
                                       selectedValue: picture.intValue("atmosphere_light_color_value", default: -1)) {
                        state.setLightColor($0)
                    }
                    if lightMode != 2 {
                        Text("选择颜色会切换到纯色模式。")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                            .padding(.leading, Theme.parameterLabelWidth + 12)
                    }
                }
            }
            .frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24).font(.system(size: 14))
        }
        .onAppear { state.refreshPage("light") }
    }
}
