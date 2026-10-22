import Foundation
import XCTest
import ToolboxConcurrency
@testable import ToolboxApplication

final class ReadinessTests: XCTestCase {
    private func client(_ result: ProcessResult, calls: @escaping (CommandRequest) -> Void) -> AdbClient {
        let adb = AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "15038",
            runtime: { _ in nil }, guardianAPK: { nil })) { request in calls(request); return result }
        adb.ip = "Monitor.local"
        return adb
    }

    private func failures(containing text: String) -> [ProcessResult] {
        [
            .init(output: text, exitCode: 1),
            .init(standardOutput: text, exitCode: 0, outcome: .timedOut),
            .init(standardOutput: text, exitCode: 0, outcome: .signalled(15)),
            .init(standardOutput: text, exitCode: 0, outcome: .launchFailed(2)),
            .init(standardOutput: text, exitCode: 0, outcome: .ioFailure(5)),
            .init(standardOutput: text, exitCode: 0, outcome: .cancelled),
            .init(standardOutput: text, exitCode: 0, outcome: .exited, outputTruncated: true),
            .init(standardError: text, exitCode: 0, outcome: .exited),
            .init(output: "prefix \(text)", exitCode: 0),
            .init(output: "\(text) suffix", exitCode: 0),
            .init(output: "\(text)\n\(text)", exitCode: 0),
            .init(output: "", exitCode: 0)
        ]
    }

    func testFailedPartialOrNonExactDeviceStateNeverEqualsReady() {
        for result in failures(containing: "device") {
            var calls: [CommandRequest] = []
            let adb = client(result) { calls.append($0) }
            XCTAssertNotEqual(adb.deviceState(), "device")
            XCTAssertEqual(calls.map(\.arguments), [["-s", "Monitor.local:5555", "get-state"]])
            XCTAssertEqual(calls.map(\.timeout), [3])
        }
    }

    func testFailedPartialOrNonExactMarkerNeverProvesTransport() {
        for result in failures(containing: "__mimonitor_probe__") {
            var calls: [CommandRequest] = []
            let adb = client(result) { calls.append($0) }
            XCTAssertFalse(adb.transportWorks())
            XCTAssertEqual(calls.map(\.arguments), [["-s", "Monitor.local:5555", "shell", "echo __mimonitor_probe__"]])
            XCTAssertEqual(calls.map(\.timeout), [25])
        }
    }

    func testSuccessfulExactStdoutPreservesLegacyWhitespaceAndArgv() {
        for text in ["device", " device\r\n"] {
            let adb = client(.init(standardOutput: text, standardError: "diagnostic", exitCode: 0, outcome: .exited)) { _ in }
            XCTAssertEqual(adb.deviceState(), "device")
        }
        for text in ["__mimonitor_probe__", " __mimonitor_probe__\r\n"] {
            let adb = client(.init(standardOutput: text, standardError: "diagnostic", exitCode: 0, outcome: .exited)) { _ in }
            XCTAssertTrue(adb.transportWorks())
        }
    }

    func testAuthorizationDiagnosticSurvivesNonzeroStderr() {
        let text = "error: device unauthorized.\nThis adb server's $ADB_VENDOR_KEYS is not set"
        let adb = client(.init(standardError: text, exitCode: 1, outcome: .exited)) { _ in }
        XCTAssertEqual(adb.deviceState(), text)
    }

    func testStrictReadinessDoesNotChangeLegacyShellContract() {
        let adb = client(.init(output: "legacy output", exitCode: 1)) { _ in }
        XCTAssertEqual(adb.shell("legacy command"), "legacy output")
    }
}
