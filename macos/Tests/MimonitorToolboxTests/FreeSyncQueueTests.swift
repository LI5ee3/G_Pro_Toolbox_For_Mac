import XCTest
import Foundation
import ToolboxConcurrency
import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class FreeSyncQueueTests: XCTestCase {
    private func fixture(_ runtime: PreviewRuntime, execute: @escaping (CommandRequest) -> ProcessResult) -> AppCoordinator {
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources, execute: execute)
        return AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, calendar: base.calendar, presetDevice: base.presetDevice))
    }
    func testRapidFreeSyncEnableDisableRestoresNewlyRememberedMode() async {
        let runtime = PreviewRuntime()
        runtime.preferences.set(14, forKey: "freesync_previous_mode")
        var enabled = false
        var commands: [String] = [] // confined to the serial worker until the await barrier
        let state = fixture(runtime) { request in
            let command = (request.arguments.last ?? "").replacingOccurrences(of: "\\${IFS}", with: " ")
            commands.append(command)
            if command.contains("batchGet") { return ProcessResult(output: "g_video__dp_adaptive_sync=\(enabled ? 1 : 0)", exitCode: 0) }
            if command == "settings get global picture_mode" { return ProcessResult(output: "9", exitCode: 0) }
            if command.contains("MtkDirectTool set g_video__dp_adaptive_sync 1") { enabled = true }
            if command.contains("MtkDirectTool set g_video__dp_adaptive_sync 0") { enabled = false }
            return runtime.display.execute(request)
        }
        state.adb.ip = "192.0.2.1"; state.connectionStatus = .connected("fake")
        // Confirmed fake ownership; this test checks the unchanged device protocol.
        state.connection.identityRestricted = false
        state.connection.presetIdentityKey = "192.0.2.1"
        state.connection.memoryOwnershipConfirmed = true
        state.connection.allowsIdentityAutomaticActions = true
        state.freesyncMemoryEnabled = true
        state.deviceQueue.suspend()
        state.setFreesync(true); state.setFreesync(false)
        state.deviceQueue.resume()
        let done = expectation(description: "FIFO controls and main publication drained")
        state.deviceQueue.async { DispatchQueue.main.async { done.fulfill() } }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(commands.contains("settings put global picture_mode 9"))
        XCTAssertFalse(commands.contains("settings put global picture_mode 14"))
        XCTAssertEqual(runtime.preferences.integer(forKey: "freesync_previous_mode"), 9)
        state.stop()
    }
}
