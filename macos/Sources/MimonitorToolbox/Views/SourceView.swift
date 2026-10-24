import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct SourceView: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @Environment(PictureModel.self) private var picture

    private var selectedSource: Int { picture.intValue("mitv.tvplayer.hdmi.last.source", default: -1) }
    private var sourceName: String {
        guard let option = OptionLists.source.first(where: { $0.value == selectedSource }) else { return "—" }
        return option.label == "DP" ? "DisplayPort" : option.label
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "信号源切换") { state.forceRefreshPage("source") }

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前视频输入").font(Theme.sectionFont)
                    Text(sourceName).font(.system(size: 24, weight: .semibold))
                        .accessibilityLabel("当前视频输入：\(sourceName == "—" ? "未知" : sourceName)")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("选择视频输入").font(Theme.sectionFont)
                    HStack(spacing: 8) {
                        ForEach(OptionLists.source) { option in
                            SelectableButton(title: option.label, isSelected: selectedSource == option.value) {
                                state.setSource(option.value)
                            }
                            .accessibilityLabel("切换到 \(option.label)")
                        }
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("ADB 控制") { Text(connection.activeControlText).textSelection(.enabled) }
                    Text("USB-C 属于视频输入；ADB 控制通道可独立选择。")
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
