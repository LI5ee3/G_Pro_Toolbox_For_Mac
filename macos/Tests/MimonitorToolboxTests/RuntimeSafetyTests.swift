import ToolboxDomain
import ToolboxApplication
@testable import ToolboxPreviewSupport
import XCTest
import MimonitorPresetCore
@testable import MimonitorToolbox

@MainActor
final class RuntimeSafetyTests: XCTestCase {
    func testRepeatedConstructionHasNoCommandsTimersOrSystemActions() {
        for _ in 0..<20 {
            let runtime = PreviewRuntime()
            autoreleasepool {
                let state = AppCoordinator(environment: runtime.environment())
                XCTAssertTrue(state.crosshairGameModeOnly)
                XCTAssertFalse(state.isRunning)
                XCTAssertEqual(runtime.scheduler.pendingCount, 0)
                XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
                XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
                XCTAssertTrue(runtime.effects.isEmpty)
            }
        }
    }

    func testSimulationStartCannotRegisterLiveServices() {
        let runtime = PreviewRuntime()
        let simulated = runtime.makeState()
        simulated.start(); simulated.start()
        XCTAssertFalse(simulated.isRunning)
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
        XCTAssertEqual(runtime.scheduler.pendingCount, 0)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
    }

    func testLiveLifecycleWithFakeEffectsIsIdempotentAndCancelsStartup() async {
        let runtime = PreviewRuntime()
        let state = AppCoordinator(environment: runtime.environment(mode: .live))
        state.start()
        let count = runtime.scheduler.pendingCount
        let starts = runtime.hotkeyDriver.starts
        state.start()
        XCTAssertEqual(runtime.scheduler.pendingCount, count)
        XCTAssertEqual(runtime.hotkeyDriver.starts, starts)
        state.stop(); state.stop()
        runtime.scheduler.advance(by: 30)
        XCTAssertFalse(state.isRunning)
        XCTAssertTrue(runtime.display.recordedCommands.allSatisfy { $0 == "start-server" })
    }

    func testSettingsAndSystemActionsOnlyUseProvidedMemoryAndFakes() async {
        let runtime = PreviewRuntime()
        let simulated = runtime.makeState()
        simulated.theme = "light"; simulated.closeBehavior = "exit"
        simulated.setAutostart(true); simulated.requestAccessibilityPermission()
        simulated.toggleLogFile(true); simulated.copyLog(); simulated.chooseLogExport()
        simulated.openLogDir(); simulated.openAdbCmd()
        await simulated.waitForPendingWork()
        XCTAssertEqual(runtime.preferences.string(forKey: "theme"), "light")
        XCTAssertEqual(runtime.preferences.string(forKey: "close_behavior"), "exit")
        XCTAssertTrue(runtime.effects.contains("terminal"))
        XCTAssertTrue(runtime.effects.contains("log.export"))
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
    }

    func testStoppingDropsQueuedHardwareActions() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.deviceQueue.suspend()
        state.key("KEYCODE_DPAD_CENTER")
        state.stop()
        state.deviceQueue.resume()
        let drained = expectation(description: "stopped queue drained")
        state.deviceQueue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
    }

    func testPreviewCanResumeAfterCanvasTemporarilyHidesIt() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.stop(); state.start()
        state.key("KEYCODE_DPAD_CENTER")
        let drained = expectation(description: "resumed simulation drained")
        state.deviceQueue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertTrue(runtime.display.recordedCommands.contains { $0.contains("KEYCODE_DPAD_CENTER") })
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
    }

    func testUnknownPreviewReadingsStayUnknownAfterRefresh() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.unknown)
        state.refreshMediaVolumeState()
        let drained = expectation(description: "unknown read drained")
        state.deviceQueue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertNil(state.dashboardVolume)
        XCTAssertNil(state.dashboardMuted)
    }

    func testDisconnectDropsQueuedVolumeWriteAndTrailingCommit() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.deviceQueue.suspend()
        state.setDashboardVolume(75)
        state.disconnectAdb()
        state.deviceQueue.resume()
        runtime.scheduler.advance(by: 1)
        let drained = expectation(description: "disconnected volume queue drained")
        state.deviceQueue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("service call audio 12") })
        XCTAssertNil(state.dashboardVolume)
    }

    func testDisconnectDropsQueuedVolumeRead() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.deviceQueue.suspend()
        state.refreshMediaVolumeState()
        state.disconnectAdb()
        state.deviceQueue.resume()
        let drained = expectation(description: "disconnected read queue drained")
        state.deviceQueue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("shell") })
        XCTAssertNil(state.dashboardMuted)
    }

    func testExplicitADBDisconnectDisablesDashboardAndStopsKeyInterception() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.mediaVolumeKeysEnabled = true
        XCTAssertTrue(state.dashboardVolumeAvailable)
        XCTAssertTrue(state.shouldHandleNativeVolume())
        state.disconnectAdb()
        XCTAssertFalse(state.dashboardVolumeAvailable)
        XCTAssertFalse(state.shouldHandleNativeVolume())
    }
}
