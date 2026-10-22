import ToolboxDomain
import Foundation

extension AppCoordinator {
    package func finishLogs(_ completion: @escaping @MainActor @Sendable () -> Void) { environment.system.finishLogs(completion) }

    package func refreshLoginItem(migrateLegacy: Bool = false) {
        guard isRunning || environment.mode == .simulation else { return }
        guard !settings.loginItemBusy else { return }
        settings.loginItemBusy = true
        let actions = environment.system
        submitSystemOperation(work: { token in
            migrateLegacy ? actions.reconcileLogin(token) : actions.loginStatus()
        }) { snapshot in
            self.settings.loginItem = snapshot
            self.settings.loginItemBusy = false
            if let error = snapshot.error { self.log(error) }
        }
    }
    package func setAutostart(_ enabled: Bool) {
        guard isRunning || environment.mode == .simulation else { return }
        guard !settings.loginItemBusy else { return }
        settings.loginItemBusy = true
        let update = environment.system.updateLogin
        submitSystemOperation(work: { update(enabled, $0) }) { snapshot in
            self.settings.loginItem = snapshot
            self.settings.loginItemBusy = false
            self.log(snapshot.detail)
        }
    }
    package func openLoginItemSettings() { environment.system.openLoginSettings() }
}
