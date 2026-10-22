import Foundation
import ToolboxDomain
import ToolboxConcurrency

package struct LegacyLoginItemRecord {
    package let bytes: Data
    package let status: LegacyLoginItemStatus
    package init(bytes: Data, status: LegacyLoginItemStatus) { self.bytes = bytes; self.status = status }
}
/// All methods execute on the dedicated system queue. Construction never reads system state.
package struct LoginItemPorts {
    package var status: () -> LoginItemStatus
    package var register: () throws -> Void
    package var unregister: () throws -> Void
    package var legacy: () throws -> LegacyLoginItemRecord?
    package var backup: (LegacyLoginItemRecord) throws -> Void
    package var retire: (LegacyLoginItemRecord) throws -> Void
    package var restore: (LegacyLoginItemRecord) throws -> Void
    package init(status: @escaping () -> LoginItemStatus, register: @escaping () throws -> Void,
                 unregister: @escaping () throws -> Void, legacy: @escaping () throws -> LegacyLoginItemRecord?,
                 backup: @escaping (LegacyLoginItemRecord) throws -> Void,
                 retire: @escaping (LegacyLoginItemRecord) throws -> Void,
                 restore: @escaping (LegacyLoginItemRecord) throws -> Void) {
        self.status = status; self.register = register; self.unregister = unregister; self.legacy = legacy
        self.backup = backup; self.retire = retire; self.restore = restore
    }
}
package final class LoginItemWorkflow {
    private let ports: LoginItemPorts
    package init(ports: LoginItemPorts) { self.ports = ports }
    package func snapshot(error: String? = nil, note: String? = nil) -> LoginItemSnapshot {
        do { return LoginItemSnapshot(status: ports.status(), legacy: try ports.legacy()?.status ?? .absent, error: error, note: note) }
        catch { return LoginItemSnapshot(status: ports.status(), legacy: .unrecognized, error: "无法读取旧登录项：\(error.localizedDescription)") }
    }
    package func reconcile(_ cancellation: CommandCancellation) -> LoginItemSnapshot {
        let current = snapshot()
        // Preserve a system denial; do not register on every activation or launch.
        guard !cancellation.isCancelled, current.legacy == .enabled,
              current.status == .notRegistered || current.status == .enabled else { return current }
        return setEnabled(true, cancellation: cancellation)
    }
    package func setEnabled(_ enabled: Bool, cancellation: CommandCancellation) -> LoginItemSnapshot {
        guard !cancellation.isCancelled else { return snapshot() }
        var legacy: LegacyLoginItemRecord?
        do {
            legacy = try ports.legacy()
            if legacy?.status == .unrecognized { return snapshot(error: "旧登录项的归属或配置无法确认，未修改。请先从原安装位置停用旧项。") }
            // Back up before changing either side. Failure leaves both untouched.
            if let legacy { try ports.backup(legacy) }
        } catch { return snapshot(error: "登录项备份失败，未修改系统设置：\(error.localizedDescription)") }
        let before = ports.status()
        if enabled, before == .requiresApproval { return snapshot() }
        var created = false
        var retired = false
        do {
            guard !cancellation.isCancelled else { return snapshot() }
            if enabled {
                if before != .enabled {
                    do { try ports.register() }
                    catch { if ports.status() != .enabled { throw error } }
                    created = true
                }
                guard ports.status() == .enabled else {
                    // Pending modern + old RunAtLoad can duplicate at the next login. Withdraw the
                    // new request while preserving the old job; never mark requiresApproval enabled.
                    if legacy != nil, created { try ports.unregister() }
                    return snapshot(note: "新登录项尚未获系统批准。旧项保留；请在登录项设置中允许后重试。")
                }
                if cancellation.isCancelled {
                    if legacy != nil, created { try ports.unregister() }
                    return snapshot()
                }
            } else if before == .enabled || before == .requiresApproval {
                try ports.unregister()
                guard ports.status() == .notRegistered || ports.status() == .notFound else {
                    return snapshot(error: "系统尚未确认注销，旧项保留，请重新检测。")
                }
            }
            if let legacy {
                retired = true // restore even when a filesystem adapter fails after the move
                try ports.retire(legacy)
            }
            return snapshot(note: legacy == nil ? nil : "旧登录项已备份并停止下次登录加载；当前应用继续运行。")
        } catch {
            var errors = [error.localizedDescription]
            if enabled, created {
                do { try ports.unregister() } catch { errors.append("撤回新项失败：\(error.localizedDescription)") }
            }
            if retired, let legacy {
                if ports.status() == .enabled || ports.status() == .requiresApproval {
                    errors.append("新项仍由系统保留，为避免重复登录启动，未自动恢复已退役的旧文件；备份仍保留")
                } else {
                    do { try ports.restore(legacy) } catch { errors.append("恢复旧项失败：\(error.localizedDescription)") }
                }
            }
            return snapshot(error: "登录项变更未完成：\(errors.joined(separator: "；"))")
        }
    }
}
