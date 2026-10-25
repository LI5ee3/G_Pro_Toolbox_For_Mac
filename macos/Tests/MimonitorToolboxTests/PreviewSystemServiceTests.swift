import XCTest
import ToolboxDomain
import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class PreviewSystemServiceTests: XCTestCase {
    func testPendingLoginApprovalAndDeniedAutomationStayTruthfulAndInMemory() async {
        let pending = PreviewRuntime(), state = pending.makeState(.loginApproval)
        state.start(); state.setAutostart(true); await state.waitForPendingWork()
        XCTAssertEqual(state.settings.loginItem.status, .requiresApproval)
        XCTAssertFalse(state.settings.autostartEnabled)
        state.openLoginItemSettings(); XCTAssertTrue(pending.effects.contains("login.settings"))
        XCTAssertEqual(pending.hotkeyDriver.starts, 0)
        let denied = PreviewRuntime(), other = denied.makeState(.permissionDenied)
        other.start(); other.openAdbCmd(); await other.waitForPendingWork()
        XCTAssertEqual(other.settings.terminalResult?.outcome, .denied)
        XCTAssertFalse(other.keyboard.accessibilityTrusted)
        XCTAssertEqual(denied.hotkeyDriver.starts, 0)
        XCTAssertEqual(denied.scheduler.pendingCount, 0)
        XCTAssertTrue(denied.display.recordedCommands.isEmpty)
        state.stop(); other.stop()
    }
}
