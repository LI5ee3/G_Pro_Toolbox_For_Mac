import Foundation
import XCTest
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

final class ServerRecoveryTests: XCTestCase {
    private final class Fixture {
        var time: TimeInterval = 100
        var calls: [CommandRequest] = []
        var response: (CommandRequest) -> ProcessResult = { request in
            if request.arguments.contains("get-state") { return ProcessResult(output: "device", exitCode: 0) }
            if request.arguments == ["host-features"] { return ProcessResult(output: "shell_v2,cmd\n", exitCode: 0) }
            return ProcessResult(output: "error: device offline", exitCode: 1)
        }
        lazy var adb = AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "5038",
            runtime: { _ in nil }, guardianAPK: { nil }), recoveryTime: { self.time }) { request in
                self.calls.append(request)
                return self.response(request)
            }
        init() { adb.ip = "192.0.2.15" }
        var argv: [[String]] { calls.map(\.arguments) }
        var queries: Int { argv.filter { $0 == ["host-features"] }.count }
        var connects: Int { argv.filter { $0 == ["connect", "192.0.2.15:5555"] }.count }
        func assertNoRestart(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertFalse(argv.contains { $0.contains("kill-server") || $0.contains("start-server") }, file: file, line: line)
            XCTAssertTrue(calls.allSatisfy { $0.serverPort == "5038" && $0.executable == "/fake/adb" }, file: file, line: line)
        }
    }

    func testHealthyTargetKeepsOriginalTwoCommandFastPath() {
        let f = Fixture()
        f.response = { ProcessResult(output: $0.arguments.contains("get-state") ? "device" : "__mimonitor_probe__", exitCode: 0) }
        XCTAssertTrue(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.argv, [["-s", "192.0.2.15:5555", "get-state"],
                                ["-s", "192.0.2.15:5555", "shell", "echo __mimonitor_probe__"]])
    }

    func testClientVersionSuccessCannotStandInForAbsentServer() {
        let f = Fixture(), original = Fixture().response
        f.response = { request in
            if request.arguments == ["version"] { return ProcessResult(output: "Android Debug Bridge version 1.0.41", exitCode: 0) }
            if request.arguments == ["host-features"] { return ProcessResult(output: "cannot connect to daemon", exitCode: 1) }
            return original(request)
        }
        XCTAssertTrue(f.adb.run(["version"]).succeeded)
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.queries, 1)
        XCTAssertEqual(f.connects, 1) // Failed server query never permits the final retry.
        XCTAssertEqual(f.calls.first { $0.arguments == ["host-features"] }?.timeout, 3)
        f.assertNoRestart()
    }

    func testUnauthorizedAtEntryDoesNotConnectProbeOrRecover() {
        for state in ["unauthorized", "error: device unauthorized.\nThis adb server's $ADB_VENDOR_KEYS is not set"] {
            let f = Fixture()
            f.response = { _ in ProcessResult(output: state, exitCode: state == "unauthorized" ? 0 : 1) }
            let result = f.adb.ensureConnected()
            XCTAssertFalse(result.ok); XCTAssertEqual(result.state, state)
            XCTAssertEqual(f.argv, [["-s", "192.0.2.15:5555", "get-state"]])
        }
    }

    func testUnauthorizedAfterConnectStopsWaitAndServerRecovery() {
        let f = Fixture()
        f.response = { request in
            ProcessResult(output: request.arguments.contains("get-state") ? (f.connects == 0 ? "offline" : "unauthorized") : "connected", exitCode: 0)
        }
        XCTAssertEqual(f.adb.ensureConnected().state, "unauthorized")
        XCTAssertEqual(f.argv, [["-s", "192.0.2.15:5555", "get-state"], ["connect", "192.0.2.15:5555"],
                                ["-s", "192.0.2.15:5555", "get-state"]])
        f.assertNoRestart()
    }

    func testHealthyServerDoesNotJustifyKillingItForFailedTarget() {
        let f = Fixture()
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.queries, 1); XCTAssertEqual(f.connects, 2)
        XCTAssertEqual(f.argv.count, 9)
        f.assertNoRestart()
    }

    func testSuccessfulServerQueryAllowsOnlyOneFinalPinnedRetry() {
        let f = Fixture(), original = Fixture().response
        f.response = { request in
            if request.arguments.last == "echo __mimonitor_probe__", f.connects == 2 {
                return ProcessResult(output: "__mimonitor_probe__", exitCode: 0)
            }
            return original(request)
        }
        XCTAssertTrue(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.connects, 2); XCTAssertEqual(f.queries, 1)
        XCTAssertEqual(f.argv[5], ["host-features"])
        f.assertNoRestart()
    }

    func testFailedEmptyTruncatedAndTimedOutServerRepliesNeverPermitRetry() {
        let results: [ProcessResult] = [
            .init(output: "shell_v2", exitCode: 1), .init(output: "\n", exitCode: 0),
            .init(standardOutput: "shell_v2", exitCode: 0, outcome: .exited, outputTruncated: true),
            .init(standardOutput: "shell_v2", exitCode: 0, outcome: .timedOut),
            .init(standardOutput: "shell_v2", exitCode: 0, outcome: .launchFailed(2)),
            .init(standardError: "shell_v2", exitCode: 0, outcome: .exited)
        ]
        for result in results {
            let f = Fixture(), original = Fixture().response
            f.response = { $0.arguments == ["host-features"] ? result : original($0) }
            XCTAssertFalse(f.adb.ensureConnected().ok)
            XCTAssertEqual(f.queries, 1); XCTAssertEqual(f.connects, 1)
            f.assertNoRestart()
        }
    }

    func testCooldownIsEnforcedAtQueryBoundaryIncludingFailedAttempts() {
        for succeeds in [true, false] {
            let f = Fixture(), original = Fixture().response
            f.response = { $0.arguments == ["host-features"] && !succeeds ? ProcessResult(output: "failed", exitCode: 1) : original($0) }
            XCTAssertFalse(f.adb.ensureConnected().ok)
            f.time += 24.999
            XCTAssertFalse(f.adb.ensureConnected().ok)
            XCTAssertEqual(f.queries, 1)
            f.time = 125
            XCTAssertFalse(f.adb.ensureConnected().ok)
            XCTAssertEqual(f.queries, 2)
            // Changing the endpoint must not reset the server-wide cooldown.
            f.adb.beginSession(ip: "192.0.2.16")
            XCTAssertFalse(f.adb.ensureConnected().ok)
            XCTAssertEqual(f.queries, 2)
            f.assertNoRestart()
        }
    }

    func testCancelledSessionDispatchesNothing() {
        let f = Fixture(); f.adb.cancelSession()
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertTrue(f.calls.isEmpty)
    }

    func testCancellationDuringServerQuerySuppressesRetryEvenWithSuccessfulReply() {
        let f = Fixture(), original = Fixture().response
        f.response = { request in
            if request.arguments == ["host-features"] { request.cancellation.cancel() }
            return original(request)
        }
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.connects, 1); XCTAssertEqual(f.argv.last, ["host-features"])
        f.assertNoRestart()
    }

    func testCancellationDuringOfflineWaitSuppressesServerRecovery() {
        let f = Fixture()
        f.response = { request in
            if f.connects == 1, request.arguments.contains("get-state") { request.cancellation.cancel() }
            return ProcessResult(output: "offline", exitCode: 0)
        }
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.calls.count, 3); XCTAssertEqual(f.queries, 0)
        f.assertNoRestart()
    }

    func testSessionReplacementDuringServerQueryCannotRetryNewTarget() {
        let f = Fixture(), original = Fixture().response
        f.response = { request in
            if request.arguments == ["host-features"] { f.adb.beginSession(ip: "192.0.2.16") }
            return original(request)
        }
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.connects, 1); XCTAssertEqual(f.argv.last, ["host-features"])
        XCTAssertFalse(f.argv.contains { $0.contains("192.0.2.16:5555") })
        XCTAssertEqual(f.adb.ip, "192.0.2.16")
    }

    @MainActor func testMonitorUsesSameAuthorizationAndCooldownBoundary() async {
        let runtime = PreviewRuntime(), base = runtime.environment(), f = Fixture()
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: f.adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, calendar: base.calendar, presetDevice: base.presetDevice))
        state.monitorAdbServer(); await state.waitForPendingWork()
        state.monitorAdbServer(); await state.waitForPendingWork()
        XCTAssertEqual(f.queries, 1); f.assertNoRestart()
        f.time = 125
        f.response = { _ in ProcessResult(output: "error: device unauthorized.", exitCode: 1) }
        state.monitorAdbServer(); await state.waitForPendingWork()
        XCTAssertEqual(f.queries, 1)
        XCTAssertFalse(state.isConnected)
        state.stop(); await state.waitForPendingWork()
    }
}
