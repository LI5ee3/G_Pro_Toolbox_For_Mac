import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct SourceView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PictureModel.self) private var picture
    @Environment(NavigationModel.self) private var navigation

    private var selectedSource: Int { picture.intValue("mitv.tvplayer.hdmi.last.source", default: -1) }
    private var sourceName: String {
        guard let option = OptionLists.source.first(where: { $0.value == selectedSource }) else { return "未知" }
        return option.label == "DP" ? "DP（DisplayPort）" : option.label
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "信号源切换") { state.forceRefreshPage("source") }

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前视频输入").font(Theme.sectionFont)
                        Text(sourceName).font(.system(size: 24, weight: .semibold))
                            .accessibilityLabel("当前视频输入：\(sourceName)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择视频输入").font(Theme.sectionFont)
                        SegmentedOptionPicker(options: OptionLists.source, selectedValue: selectedSource,
                                              controlSize: .regular) { state.setSource($0) }
                            .frame(width: 360).accessibilityLabel("选择视频输入")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        LabeledContent("ADB 控制") {
                            Text(connection.activeControlText).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("连接设置…") { navigation.showsConnectionSettings = true }
                            .buttonStyle(.borderless).foregroundStyle(Theme.accent).fixedSize()
                    }
                    Text("切换视频输入不会更改 ADB 控制通道。")
                        .foregroundStyle(Theme.secondaryText)
                }.font(.system(size: 13))
            }
            .padding(24).frame(maxWidth: 970, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { state.refreshPage("source") }
        .loadingOverlay(picture.loadingPages.contains("source"))
    }
}
