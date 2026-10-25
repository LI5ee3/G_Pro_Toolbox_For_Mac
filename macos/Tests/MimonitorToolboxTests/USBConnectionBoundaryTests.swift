import XCTest
import Foundation
import ToolboxDomain
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class USBConnectionBoundaryTests: XCTestCase {
    private func fixture() -> (AppCoordinator, PreviewRuntime, () -> [[String]]) {
        let runtime = PreviewRuntime(), base = runtime.environment()
        let lock = NSLock()
        var calls: [[String]] = []
        let adb = AdbClient(resources: base.adb.resources) { request in
            lock.lock(); calls.append(request.arguments); lock.unlock()
            switch request.arguments {
            case ["devices", "-l"]:
                return ProcessResult(output: "List of devices attached\n000USB_A device usb:1-2\n\n", exitCode: 0)
            case ["-s", "000USB_A", "get-state"]:
                return ProcessResult(output: "device", exitCode: 0)
            case ["-s", "000USB_A", "shell", "echo __mimonitor_probe__"]:
                return ProcessResult(output: "__mimonitor_probe__", exitCode: 0)
            default:
                XCTFail("Unexpected production command: \(request.arguments)")
                return ProcessResult(output: "rejected", exitCode: 1)
            }
        }
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, presetDevice: base.presetDevice))
        return (state, runtime, { lock.lock(); defer { lock.unlock() }; return calls })
    }

    func testUnactivatedUSBSelectionCannotFallBackToSavedTCPOrStartInitialization() async {
        let (state, runtime, calls) = fixture()
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        let result = state.adb.validateUSBSelection(serial: "000USB_A")
        XCTAssertNotNil(result.endpoint)
        XCTAssertNil(state.adb.endpoint, "Validation must not activate a session")
        state.adb.beginSession(endpoint: result.endpoint)
        let token = state.adb.session().cancellation
        let before = calls()
        state.monitorAdbServer(refreshState: true)
        await state.waitForPendingWork()
        XCTAssertEqual(calls(), before)
        XCTAssertEqual(state.adb.serial, "000USB_A")
        XCTAssertTrue(state.adb.session().cancellation === token)
        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
        XCTAssertNil(runtime.preferences.data(forKey: "picture_presets_v1"))
        state.stop()
    }

    func testUSBLogicalDisconnectCancelsAndSuppressesRecoveryWithoutTCPDisconnect() async {
        let (state, runtime, calls) = fixture()
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        let endpoint = state.adb.validateUSBSelection(serial: "000USB_A").endpoint
        XCTAssertNotNil(endpoint)
        state.adb.beginSession(endpoint: endpoint)
        state.connectionStatus = .connected("synthetic USB")
        let old = state.adb.session(), child = old.childOperation()
        let before = calls()
        state.disconnectAdb()
        await state.waitForPendingWork()
        XCTAssertTrue(old.cancellation.isCancelled)
        XCTAssertTrue(child.cancellation.isCancelled)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        state.monitorAdbServer(refreshState: true)
        state.recoverAfterWake()
        runtime.scheduler.advance(by: 60)
        await state.waitForPendingWork()
        XCTAssertEqual(calls(), before)
        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
        state.stop()
    }
}
