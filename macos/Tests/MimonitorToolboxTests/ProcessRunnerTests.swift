import XCTest
import Foundation
import Darwin
import ToolboxConcurrency
import ToolboxProcessExecution

final class ProcessRunnerTests: XCTestCase {
    private func request(_ script: String, timeout: Double = 2,
                         token: CommandCancellation = CommandCancellation()) -> CommandRequest {
        CommandRequest(executable: "/bin/sh", arguments: ["-c", script], serverPort: "65038",
                       timeout: timeout, cancellation: token)
    }
    func testSeparateStreamsExitStatusAndServerEnvironment() {
        let result = SystemProcessRunner.run(request("printf '%s' \"$ANDROID_ADB_SERVER_PORT\"; printf err >&2; exit 7"))
        XCTAssertEqual(result.standardOutput, "65038")
        XCTAssertEqual(result.standardError, "err")
        XCTAssertEqual(result.output, "65038err")
        XCTAssertEqual(result.exitCode, 7); XCTAssertEqual(result.outcome, .exited)
        XCTAssertFalse(result.succeeded)
    }
    func testLargeDoublePipeOutputDoesNotDeadlockOrLoseData() {
        let result = SystemProcessRunner.run(request("dd if=/dev/zero bs=1048576 count=2 2>/dev/null & (dd if=/dev/zero bs=1048576 count=2 2>/dev/null) >&2; wait"))
        XCTAssertTrue(result.succeeded, "\(result.outcome)")
        XCTAssertEqual(result.standardOutput.utf8.count, 2 * 1048576)
        XCTAssertEqual(result.standardError.utf8.count, 2 * 1048576)
    }
    func testHardDeadlineEscalatesWhenTermIsIgnored() {
        let start = Date()
        let result = SystemProcessRunner.run(request("trap '' TERM; printf ready; while :; do sleep 1; done", timeout: 0.1))
        XCTAssertEqual(result.outcome, .timedOut); XCTAssertEqual(result.exitCode, -1)
        XCTAssertTrue(result.output.contains("ready"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }
    func testCancellationBeforeLaunchHasNoEffects() {
        let token = CommandCancellation(); token.cancel()
        let result = SystemProcessRunner.run(request("echo should-not-run", token: token))
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(result.standardOutput, "")
    }
    func testCancellationDuringProcessStopsItWithinBound() {
        let token = CommandCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { token.cancel() }
        let start = Date()
        let result = SystemProcessRunner.run(request("trap '' TERM; while :; do sleep 1; done", token: token))
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }
    func testDescendantHoldingPipesCannotHoldRunnerOpen() {
        let start = Date()
        let result = SystemProcessRunner.run(request("sleep 30 & echo $!; exit 0"))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        if let pid = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Child can briefly be a zombie awaiting its new parent's reap; it cannot retain pipes.
            let probe = SystemProcessRunner.run(request("ps -p \(pid) -o stat="))
            XCTAssertTrue(probe.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || probe.output.contains("Z"))
        } else { XCTFail("missing descendant pid") }
    }
    func testCancellationKillsTermIgnoringDescendantEvenAfterItClosesBothPipes() {
        let result = SystemProcessRunner.run(request("sh -c 'trap \"\" TERM; exec >/dev/null 2>&1; while :; do sleep 1; done' & echo $!; wait", timeout: 0.1))
        XCTAssertEqual(result.outcome, .timedOut)
        guard let pid = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)) else { return XCTFail("missing child pid") }
        // Safe cleanup if this test ever regresses: this PID was emitted by our own fake process.
        defer { _ = kill(pid, SIGKILL) }
        let probe = SystemProcessRunner.run(request("ps -p \(pid) -o stat="))
        XCTAssertTrue(probe.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || probe.output.contains("Z"), probe.output)
    }
    func testSignalAndLaunchFailureAreStructured() {
        XCTAssertEqual(SystemProcessRunner.run(request("kill -KILL $$")).outcome, .signalled(SIGKILL))
        let missing = SystemProcessRunner.run(CommandRequest(executable: "/nonexistent/toolbox-test", arguments: [], serverPort: "0", timeout: 1))
        XCTAssertEqual(missing.outcome, .launchFailed(ENOENT)); XCTAssertEqual(missing.exitCode, -1)
    }
    func testFloodStillObservesDeadlineAndBoundsMemory() {
        let start = Date()
        let result = SystemProcessRunner.run(request("exec /usr/bin/yes x", timeout: 0.25))
        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertLessThanOrEqual(result.standardOutput.utf8.count, 16 * 1048576)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }
    func testExitCancellationRacesAlwaysFinishOnce() {
        for _ in 0..<20 {
            let token = CommandCancellation()
            DispatchQueue.global().async { token.cancel() }
            let result = SystemProcessRunner.run(request("exit 0", token: token))
            XCTAssertTrue(result.outcome == .exited || result.outcome == .cancelled)
        }
    }
    func testClosingBothPipesDoesNotDisableTheProcessDeadline() {
        let start = Date()
        let result = SystemProcessRunner.run(request("exec 1>&- 2>&-; sleep 20", timeout: 0.05))
        XCTAssertEqual(result.outcome, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testInvalidDeadlineDoesNotLaunch() {
        XCTAssertEqual(SystemProcessRunner.run(request("exit 0", timeout: .nan)).outcome, .timedOut)
        XCTAssertEqual(SystemProcessRunner.run(request("exit 0", timeout: 0)).outcome, .timedOut)
    }
}
