import ToolboxDomain
import ToolboxApplication
import SwiftUI

struct SourceView: View {
    @ToolboxActions var state

    private var selectedSource: Int {
        state.intValue("mitv.tvplayer.hdmi.last.source", default: -1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "信号源切换") { state.forceRefreshPage("source") }

                MonitorHardwareView {
                    VStack(spacing: 10) {
                        Text("当前信号源")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Text(state.activeSource)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Label(state.isConnected ? "已连接" : "未连接", systemImage: state.isConnected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.control)
                }
                .frame(height: 290)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 14) {
                    Text("选择信号源").font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                        ForEach(OptionLists.source) { opt in
                            sourceButton(opt)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .onAppear { state.refreshPage("source") }
        .loadingOverlay(state.loadingPages.contains("source"))
    }

    private func sourceButton(_ option: Option) -> some View {
        let selected = selectedSource == option.value
        return Button {
            state.setSource(option.value)
        } label: {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: option.value == 30 ? "cable.connector" : "display")
                        .font(.system(size: 21, weight: .regular))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .opacity(selected ? 1 : 0.3)
                }
                Text(option.label)
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(selected ? Theme.accent : .primary)
            .padding(14)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .toolboxAction()
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.accent : .clear, lineWidth: 1.5))
        .accessibilityLabel("切换到 \(option.label)")
        .accessibilityValue(selected ? "已选择" : "未选择")
        .help("切换到 \(option.label)")
    }
}
