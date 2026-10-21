import Foundation

package enum LoginItemStatus: String, Sendable, CaseIterable {
    case notRegistered, enabled, requiresApproval, notFound, unavailable
}
package enum LegacyLoginItemStatus: Sendable { case absent, enabled, disabled, unrecognized }
package struct LoginItemSnapshot: Sendable, Equatable {
    package var status: LoginItemStatus
    package var legacy: LegacyLoginItemStatus
    package var error: String?
    package var note: String?
    package init(status: LoginItemStatus = .notRegistered, legacy: LegacyLoginItemStatus = .absent,
                 error: String? = nil, note: String? = nil) {
        self.status = status; self.legacy = legacy; self.error = error; self.note = note
    }
    package var enabled: Bool { status == .enabled || legacy == .enabled }
    package var needsAttention: Bool { error != nil || status == .requiresApproval || status == .notFound || legacy == .unrecognized }
    package var detail: String {
        if let error { return error }
        if let note { return note }
        switch status {
        case .enabled: return "登录项已启用，状态由系统回读。"
        case .requiresApproval: return "需要在系统的登录项设置中允许本应用。"
        case .notFound: return "系统未找到有效的应用服务，请检查安装位置与代码签名。"
        case .unavailable: return "无法读取系统登录项状态。"
        case .notRegistered:
            if legacy == .enabled { return "旧登录项仍保留，尚未完成迁移。" }
            if legacy == .disabled { return "旧登录项被系统禁用，未自动重新启用。" }
            return "登录项未启用。"
        }
    }
}

package enum AppLaunchPolicy {
    package static func startsInMenuBar(arguments: [String], loginEvent: Bool) -> Bool {
        loginEvent || arguments.contains("--minimized")
    }
}
