import XCTest
import Foundation
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class ConnectionConcurrencyTests: XCTestCase {
    private func fixture(_ runtime: PreviewRuntime, execute: @escaping (CommandRequest) -> ProcessResult) -> AppCoordinator {
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources, execute: execute)
        return AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, presetDevice: base.presetDevice))
    }
    func testConnectionACompletingAfterBWasRequestedCannotOverwriteB() async {
        let runtime = PreviewRuntime(), began = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let state = fixture(runtime) { request in
            if request.arguments.contains("192.0.2.1:5555"), request.arguments.last == "echo __mimonitor_probe__" {
                began.signal(); _ = release.wait(timeout: .now() + 2)
            }
            return runtime.display.execute(request)
        }
        state.ipInput = "192.0.2.1"; state.connect()
        XCTAssertEqual(began.wait(timeout: .now() + 2), .success)
        // This must return on MainActor even while A owns the protocol lock.
        state.ipInput = "192.0.2.2"; state.connect()
        release.signal()
        await state.waitForPendingWork()
        XCTAssertEqual(state.adb.ip, "192.0.2.2")
        XCTAssertTrue(state.connection.statusText.contains("192.0.2.2"))
        XCTAssertFalse(state.connection.statusText.contains("192.0.2.1"))
        XCTAssertTrue(state.connection.isConnected)
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("192.0.2.1:5555") }.count, 1)
        state.stop()
    }
    func testDisconnectDuringProbeDropsResultAndDoesNotRecoverAutomatically() async {
        let runtime = PreviewRuntime(), began = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let state = fixture(runtime) { request in
            if request.arguments.last == "echo __mimonitor_probe__" {
                began.signal(); _ = release.wait(timeout: .now() + 2)
            }
            return runtime.display.execute(request)
        }
        state.ipInput = "192.0.2.1"; state.connect()
        XCTAssertEqual(began.wait(timeout: .now() + 2), .success)
        state.disconnectAdb(); release.signal()
        await state.waitForPendingWork()
        runtime.scheduler.advance(by: 60)
        XCTAssertFalse(state.connection.isConnected)
        XCTAssertEqual(state.adb.ip, "")
        XCTAssertTrue(state.picture.currentValues.isEmpty)
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        XCTAssertTrue(runtime.display.recordedCommands.contains("disconnect 192.0.2.1:5555"))
    }
    func testStoppingCancelsActiveOperationAndRestartCanSubmitNewWork() async {
        let runtime = PreviewRuntime(), began = DispatchSemaphore(value: 0)
        let state = fixture(runtime) { request in
            began.signal()
            _ = request.cancellation.sleep(for: 10)
            return .cancelled
        }
        state.adb.ip = "192.0.2.1"
        state.connectionStatus = .connected("fake")
        state.key("KEYCODE_DPAD_CENTER")
        XCTAssertEqual(began.wait(timeout: .now() + 2), .success)
        let session = state.adb.session()
        state.stop()
        XCTAssertTrue(session.cancellation.isCancelled)
        state.start()
        XCTAssertFalse(state.adb.session().cancellation.isCancelled)
        state.stop()
        await state.waitForPendingWork()
    }
}
