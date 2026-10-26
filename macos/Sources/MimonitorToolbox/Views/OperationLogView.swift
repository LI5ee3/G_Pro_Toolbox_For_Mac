import SwiftUI
import ToolboxApplication

struct OperationLogView: View {
    @ToolboxActions var state
    @Environment(LogModel.self) private var logs
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("操作日志").font(Theme.pageTitle)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(logs.lines.enumerated()), id: \.offset) { index, line in
                            Text(line).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: logs.sequence) {
                    guard let last = logs.lines.indices.last else { return }
                    DispatchQueue.main.async { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            HStack {
                Toggle("记录到本地文件", isOn: Binding(get: { logs.recordsToFile }, set: { state.toggleLogFile($0) }))
                Spacer()
                Button("复制全部") {
                    state.copyLog()
                }.toolboxAction()
                Button("导出日志") { state.chooseLogExport() }.toolboxAction()
                Button("打开目录") { state.openLogDir() }.toolboxAction()
            }.font(Theme.detailFont)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas).tint(Theme.accent)
    }
}
