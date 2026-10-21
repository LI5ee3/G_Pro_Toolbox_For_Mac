import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct PictureView: View {
    @ToolboxActions var state
    @Environment(PictureModel.self) private var picture
    @Environment(PresetsModel.self) private var presets

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "画面设置") { state.forceRefreshPage("picture") }

                if presets.presetConfiguration.applicationIncomplete {
                    Label("上次预设未完整应用。请到预设模式重新应用或返回无预设，确认前暂停自动保存。", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                if state.activePresetID != nil {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前预设：\(state.activePresetName)")
                                .font(.system(size: 14, weight: .semibold))
                            Text("调整会自动保存到此预设；HDR/FreeSync 记忆已暂停。")
                                .font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                        }
                        Spacer(minLength: 12)
                        Button("管理预设") { state.requestedPage = .presets }
                            .toolboxAction()
                    }
                    .padding(.horizontal, 2)
                }

                // 画面模式
                SectionCard(title: "画面模式") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            ForEach([14, 9, 10], id: \.self) { v in
                                SelectableButton(title: RegisterMap.modeNames[v] ?? "\(v)",
                                                 isSelected: picture.intValue("picture_mode", default: -1) == v) {
                                    state.setMode(v)
                                }
                            }
                            Spacer(minLength: 12)
                            Button("恢复默认") { state.resetCurrentMode() }
                                .toolboxAction()
                        }
                        Divider().overlay(Theme.stroke)
                        HStack(alignment: .center, spacing: 16) {
                            Text(picture.pictureModeHint.replacingOccurrences(of: "（[0-9]+）", with: "", options: .regularExpression))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            // 光感状态以 MTK 侧回读为准。
                            Toggle("自动调整亮度", isOn: Binding(
                                get: { picture.intValue("tv_picture_light_sensor", default: 0) == 1 },
                                set: { state.setLightSensor($0) }
                            ))
                            .toggleStyle(.switch)
                            .fixedSize()
                        }
                    }
                }

                parameterHeading("基础画面", systemImage: "slider.horizontal.3")
                LazyVGrid(columns: parameterColumns, spacing: 8) {
                    // 滑条
                    SliderRow(title: "背光", range: ControlRanges.backlight.sliderBounds,
                              externalValue: picture.intValue("picture_backlight", default: 50)) { v in
                        state.setPictureSlider(title: "背光", value: v,
                                               jniKey: "g_disp__disp_back_light",
                                               settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"])
                    }
                    SliderRow(title: "黑色级别", range: ControlRanges.percentage.sliderBounds,
                              externalValue: picture.intValue("picture_brightness", default: 50)) { v in
                        state.setPictureSlider(title: "黑色级别", value: v, jniKey: nil,
                                               settingsKeys: ["picture_brightness"])
                    }
                    SliderRow(title: "对比度", range: ControlRanges.percentage.sliderBounds,
                              externalValue: picture.intValue("picture_contrast", default: 50)) { v in
                        state.setPictureSlider(title: "对比度", value: v, jniKey: nil,
                                               settingsKeys: ["picture_contrast"])
                    }
                    SliderRow(title: "饱和度", range: ControlRanges.percentage.sliderBounds,
                              externalValue: picture.intValue("picture_saturation", default: 50)) { v in
                        state.setPictureSlider(title: "饱和度", value: v, jniKey: nil,
                                               settingsKeys: ["picture_saturation"])
                    }
                    SliderRow(title: "色调", range: ControlRanges.percentage.sliderBounds,
                              externalValue: picture.intValue("picture_hue", default: 50)) { v in
                        state.setPictureSlider(title: "色调", value: v, jniKey: nil,
                                               settingsKeys: ["picture_hue"])
                    }
                    SliderRow(title: "锐度", range: ControlRanges.percentage.sliderBounds,
                              externalValue: picture.intValue("picture_sharpness", default: 50)) { v in
                        state.setPictureSlider(title: "锐度", value: v, jniKey: nil,
                                               settingsKeys: ["picture_sharpness"])
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("色彩").font(.system(size: 15, weight: .semibold))
                    parameterRow(title: "色温", options: OptionLists.colorTemp,
                                 selectedValue: picture.intValue("picture_color_temperature", default: 1)) { v in
                        state.setColorTemp(v)
                    }
                    parameterRow(title: "色域", options: OptionLists.gamut,
                                 selectedValue: picture.intValue("tv_picture_advanced_video_color_space", default: 0)) { v in
                        state.setGamut(v)
                    }
                }

                // 自定义色温才显示增益
                if picture.isCustomColorTemp {
                    LazyVGrid(columns: parameterColumns, spacing: 8) {
                        SliderRow(title: "红色增益", range: ControlRanges.colorGain.sliderBounds,
                                  externalValue: picture.intValue("picture_red_gain", default: 1024)) { v in
                            state.setColorGain(title: "红色增益", settingsKey: "picture_red_gain",
                                               jniKey: "g_video__clr_gain_r", value: v)
                        }
                        SliderRow(title: "绿色增益", range: ControlRanges.colorGain.sliderBounds,
                                  externalValue: picture.intValue("picture_green_gain", default: 1024)) { v in
                            state.setColorGain(title: "绿色增益", settingsKey: "picture_green_gain",
                                               jniKey: "g_video__clr_gain_g", value: v)
                        }
                        SliderRow(title: "蓝色增益", range: ControlRanges.colorGain.sliderBounds,
                                  externalValue: picture.intValue("picture_blue_gain", default: 1024)) { v in
                            state.setColorGain(title: "蓝色增益", settingsKey: "picture_blue_gain",
                                               jniKey: "g_video__clr_gain_b", value: v)
                        }
                    }
                }

                Divider().overlay(Theme.stroke.opacity(0.6)).padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 14) {
                    Text("光影与响应").font(.system(size: 15, weight: .semibold))
                    parameterRow(title: "精密控光", options: OptionLists.localDimming,
                                 selectedValue: picture.intValue("picture_local_dimming", default: 3)) { v in
                        state.setLocalDimming(v)
                    }

                    // 只在部分画面模式下存在这一项；SDR 模式（如标准/电影）下原版会隐藏。
                    if state.showHdrToneMapping {
                        parameterRow(title: "HDR 色调映射", options: OptionLists.hdrToneMapping,
                                     selectedValue: picture.intValue("settings_display_hdr_color_tone", default: 0)) { v in
                            state.setHdrToneMapping(v)
                        }
                    }
                    parameterRow(title: "动态清晰度", options: OptionLists.dynamicDefinition,
                                 selectedValue: picture.intValue("picture_dynamic_definition", default: 0)) { v in
                        state.setDynamicDefinition(v)
                    }
                    parameterRow(title: "灰阶响应时间", options: OptionLists.responseTime,
                                 selectedValue: picture.intValue("picture_response_time", default: 1)) { v in
                        state.setResponseTime(v)
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .font(.system(size: 14))
        }
        .disabled(presets.presetConfiguration.applicationIncomplete)
        .onAppear { state.refreshPage("picture") }
        .loadingOverlay(picture.loadingPages.contains("picture"))
    }

    private var parameterColumns: [GridItem] {
        [GridItem(.flexible(minimum: 330), spacing: 16),
         GridItem(.flexible(minimum: 330), spacing: 16)]
    }

    private func parameterRow(title: String, options: [Option], selectedValue: Int,
                              onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 112, alignment: .leading)
            HStack(spacing: 7) {
                ForEach(options) { option in
                    SelectableButton(title: option.label, isSelected: option.value == selectedValue) {
                        onSelect(option.value)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func parameterHeading(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.secondaryText)
            .padding(.top, 4)
    }
}
