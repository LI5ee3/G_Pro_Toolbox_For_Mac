import Foundation
import SwiftUI
import ToolboxApplication

struct ConnectionIdentityControls: View {
    @ToolboxActions var state
    @Environment(ConnectionModel.self) private var connection
    @State private var showConfirmation = false
    @State private var confirmationSession: UUID?
    @State private var confirmationProfileToken = ""
    @State private var confirmationText = ""
    @State private var canConfirmMemories = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(connection.identityText).font(.system(size: 13))
            if connection.identityOperationBusy {
                HStack { ProgressView().controlSize(.small); Text("正在提交连接偏好或归属确认…") }
                    .font(.system(size: 12))
            } else if !connection.profileMessage.isEmpty {
                Text(connection.profileMessage).font(.system(size: 12)).foregroundColor(Theme.secondaryText)
            }
            HStack {
                Button("保存当前连接偏好") { ConnectionDraft.saveCurrentPreference(using: state) }
                    .toolboxAction().disabled(!connection.isConnected || connection.activeEndpoint == nil || connection.identityOperationBusy || connection.identityConflict)
                Button("确认数据归属…") {
                    confirmationSession = connection.identitySessionID
                    confirmationProfileToken = connection.ownershipConfirmationToken
                    confirmationText = "当前端点：\(connection.transportText)\n\(connection.identityText)\n\(connection.ownershipConfirmationText)\n确认只登记归属，不部署组件或执行设备设置。全局记忆包括 HDR/SDR、FreeSync 和准星联动；已有开关值保持。身份不足时确认只限本次会话，自动功能保持暂停。"
                    canConfirmMemories = connection.identityEvidence != nil
                    showConfirmation = true
                }.toolboxAction().disabled(!connection.isConnected || connection.identityConflict || connection.identityOperationBusy)
            }
            Text("保存对象：\(connection.activeControlText)。未连接的草稿不保存；下次启动会重新验证身份。")
                .font(.system(size: 12)).foregroundColor(Theme.secondaryText)
        }
        .confirmationDialog("确认当前设备的数据归属", isPresented: $showConfirmation, titleVisibility: .visible) {
            if canConfirmMemories {
                Button("确认预设与全局记忆归属") { confirm(includeMemories: true) }
            }
            Button("仅确认预设归属") { confirm(includeMemories: false) }
            Button("取消", role: .cancel) {}
        } message: { Text(confirmationText) }
    }

    private func confirm(includeMemories: Bool) {
        guard let confirmationSession else { return }
        state.confirmConnectionOwnership(includeMemories: includeMemories, expectedSessionID: confirmationSession, expectedProfileToken: confirmationProfileToken)
    }
}
