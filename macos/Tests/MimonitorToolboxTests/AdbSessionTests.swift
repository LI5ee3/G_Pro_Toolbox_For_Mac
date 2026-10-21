import XCTest
import Foundation
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

final class AdbSessionTests: XCTestCase {
    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "0", runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
    }
    func testSwitchDuringTransactionCancelsRemainingCommandsInsteadOfRedirectingThem() {
        var calls: [[String]] = []
        var adb: AdbClient!
        adb = client { request in
            calls.append(request.arguments)
            adb.ip = "192.0.2.2"
            return ProcessResult(output: "done", exitCode: 0)
        }
        adb.ip = "192.0.2.1"
        let session = adb.session()
        adb.withSession(session) {
            adb.settingsPut("picture_mode", "14")
            adb.keyevent("KEYCODE_DPAD_CENTER")
            XCTAssertEqual(adb.serial, "192.0.2.1:5555")
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0][1], "192.0.2.1:5555")
        XCTAssertTrue(session.cancellation.isCancelled)
        XCTAssertEqual(adb.serial, "192.0.2.2:5555")
    }
    func testReconnectingSameAddressStillInvalidatesOldSession() {
        let adb = client { _ in XCTFail("stale work executed"); return ProcessResult(output: "", exitCode: 0) }
        adb.beginSession(ip: "192.0.2.1")
        let previous = adb.session()
        adb.beginSession(ip: "192.0.2.1")
        let result = adb.withSession(previous) { adb.run(["-s", adb.serial, "get-state"]) }
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertFalse(adb.session().cancellation.isCancelled)
    }
    func testEmptyTargetNeverFallsThroughToAdbDefaultDevice() {
        let adb = client { _ in XCTFail("empty -s executed"); return ProcessResult(output: "", exitCode: 0) }
        XCTAssertEqual(adb.shell("input keyevent KEYCODE_POWER"), "未连接显示器")
    }
    func testBinderCapabilityIsSeparateForEachDisplay() {
        var calls: [String] = []
        let adb = client { request in
            calls.append(request.arguments.joined(separator: " "))
            if request.arguments[1].hasPrefix("192.0.2.1") { return ProcessResult(output: "Parcel: Exception occurred", exitCode: 0) }
            if request.arguments.last?.contains("audio 22") == true { return ProcessResult(output: "Result: Parcel(00000000 0000000c)", exitCode: 0) }
            return ProcessResult(output: "Result: Parcel(00000000)", exitCode: 0)
        }
        adb.ip = "192.0.2.1"; XCTAssertFalse(adb.setMediaVolume(12))
        adb.ip = "192.0.2.2"; XCTAssertTrue(adb.setMediaVolume(12))
        XCTAssertTrue(calls.contains { $0.contains("192.0.2.2:5555 shell service call audio 12") })
    }
    func testTimedOutPartialOutputCannotProveTransportOrPassCheckedShell() {
        let adb = client { _ in ProcessResult(standardOutput: "__mimonitor_probe__", exitCode: -1, outcome: .timedOut) }
        adb.ip = "192.0.2.1"
        XCTAssertFalse(adb.transportWorks())
        XCTAssertThrowsError(try adb.checkedShell("echo ok", target: adb.serial))
    }
    func testOperationCancellationInterruptsProtocolSettleSleep() {
        let adb = client { _ in ProcessResult(output: "", exitCode: 0) }
        let session = adb.session()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { session.cancellation.cancel() }
        let start = Date()
        adb.withSession(session) { XCTAssertFalse(adb.pause(10)) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }
}

@MainActor
final class SessionPublicationTests: XCTestCase {
    func testQueuedCallbackFromOldTargetCannotChangeNewModel() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let queued = DispatchSemaphore(value: 0)
        state.runBackground {
            state.publish { state.volume.dashboardVolume = 99 }
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
        state.adb.beginSession(ip: "192.0.2.2")
        await Task.yield()
        let done = expectation(description: "main publication drained")
        DispatchQueue.main.async { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(state.volume.dashboardVolume, 10)
    }
    func testQueuedRemoteCommandForAIsDroppedAfterSwitchToB() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.deviceQueue.suspend()
        state.key("KEYCODE_DPAD_CENTER")
        state.adb.beginSession(ip: "192.0.2.2")
        state.deviceQueue.resume()
        let done = expectation(description: "queue drained")
        state.deviceQueue.async { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
    }
}

@MainActor
final class SessionCleanupTests: XCTestCase {
    func testCancelledQueuedPresetReleasesBusyState() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.deviceQueue.suspend()
        state.createPreset(name: "must not be saved")
        XCTAssertTrue(state.presets.isPresetOperationInFlight)
        state.adb.beginSession(ip: "192.0.2.2")
        state.deviceQueue.resume()
        for _ in 0..<100 where state.presets.isPresetOperationInFlight {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(state.presets.isPresetOperationInFlight)
        XCTAssertFalse(state.presets.isPresetBusy)
        XCTAssertTrue(state.presets.presetConfiguration.presets.isEmpty)
    }
    func testOldCompletionAfterStopAndRestartCannotPublishIntoNewLifetime() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let began = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        state.runBackground {
            began.signal(); _ = release.wait(timeout: .now() + 2)
            state.publishCompletion { state.volume.dashboardVolume = 99 }
        }
        XCTAssertEqual(began.wait(timeout: .now() + 2), .success)
        state.stop(); state.start()
        state.seedSimulationReadings(volume: 25, muted: false)
        release.signal()
        let done = expectation(description: "old completion drained")
        state.deviceQueue.async { DispatchQueue.main.async { done.fulfill() } }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(state.volume.dashboardVolume, 25)
    }
}
