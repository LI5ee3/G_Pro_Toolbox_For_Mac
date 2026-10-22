import Foundation
import XCTest
import ToolboxConcurrency
import ToolboxDomain
@testable import ToolboxApplication

final class USBSelectionTests: XCTestCase {
    private let serial = "000AbC-_9.z"
    private func list(_ rows: String) -> String { "List of devices attached\n\(rows)\n\n" }

    private final class Fixture {
        var rows = "000AbC-_9.z device usb:synthetic-1"
        var calls: [CommandRequest] = []
        var response: ((CommandRequest) -> ProcessResult?)?
        lazy var adb = AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "15038",
            runtime: { _ in nil }, guardianAPK: { nil })) { request in
                self.calls.append(request)
                if let result = self.response?(request) { return result }
                let output: String
                switch request.arguments.last {
                case "-l": output = "List of devices attached\n\(self.rows)\n\n"
                case "get-devpath": output = "usb:synthetic-1\n"
                case "get-state": output = "device\n"
                case "echo __mimonitor_probe__": output = "__mimonitor_probe__\n"
                default: XCTFail("Unexpected command: \(request.arguments)"); output = ""
                }
                return ProcessResult(output: output, exitCode: 0)
            }
        var argv: [[String]] { calls.map(\.arguments) }
    }

    private func candidate(_ rows: String) throws -> AdbDiscoveredDevice {
        guard case .complete(let devices) = AdbDeviceListParser.parse(list(rows)) else {
            throw NSError(domain: "Invalid fixture", code: 1)
        }
        return try XCTUnwrap(devices.first)
    }

    private func endpoint() throws -> AdbEndpoint {
        try XCTUnwrap(AdbEndpoint.usb(discovered: candidate("\(serial) device usb:synthetic-1")))
    }

    private var healthyTrace: [[String]] {
        [["devices", "-l"], ["-s", serial, "get-state"], ["-s", serial, "shell", "echo __mimonitor_probe__"]]
    }

    func testEndpointPreservesRawUSBSerialAndKeepsTCPCompatibilityProjection() throws {
        let usb = try endpoint()
        XCTAssertTrue(usb.isUSB)
        XCTAssertEqual(usb.serial, serial)
        XCTAssertEqual(usb.tcpHost, "")
        XCTAssertFalse(try XCTUnwrap(AdbEndpoint.tcp(host: "Monitor.Local")).isUSB)
        XCTAssertEqual(AdbEndpoint.tcp(host: "Monitor.Local")?.serial, "Monitor.Local:5555")
        for rows in ["\(serial) device", "\(serial) future-state usb:1", "\(serial) device usb:1\n\(serial) offline usb:2",
                     "Monitor.local:5555 device", "emulator-5554 device usb:1"] {
            XCTAssertNil(AdbEndpoint.usb(discovered: try candidate(rows)), rows)
        }
    }

    func testSupplementalEvidenceCannotTurnTCPUnsupportedOrAmbiguousIntoUSB() throws {
        for rows in ["Monitor.local:5555 device", "emulator-5554 device", "\(serial) device usb:1 usb:2",
                     "\(serial) device\n\(serial) unknown", "\(serial) future-state"] {
            XCTAssertNil(AdbEndpoint.usb(discovered: try candidate(rows), verifiedDevicePath: "usb:synthetic-1"), rows)
        }
        let unknown = try candidate("\(serial) device")
        XCTAssertEqual(AdbEndpoint.usb(discovered: unknown, verifiedDevicePath: "usb:synthetic-1")?.serial, serial)
        for path in ["unknown", "synthetic-1", "usb:", " usb:1", "usb:1 ", "usb:1\nusb:2", "usb:\u{7f}", "usb:" + String(repeating: "a", count: 4096)] {
            XCTAssertNil(AdbEndpoint.usb(discovered: unknown, verifiedDevicePath: path), path)
        }
    }

    func testFreshValidationHasExactReadOnlyTraceAndDoesNotActivateOrCancelTCP() {
        let f = Fixture()
        f.adb.beginSession(ip: "192.0.2.20")
        let before = f.adb.session()
        let result = f.adb.validateUSBSelection(serial: serial)
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.readiness, .ready)
        XCTAssertEqual(result.endpoint?.serial, serial)
        XCTAssertEqual(result.diagnostic, "device")
        XCTAssertEqual(f.argv, healthyTrace)
        XCTAssertEqual(f.calls.map(\.timeout), [3, 3, 25])
        XCTAssertTrue(f.calls.allSatisfy { $0.executable == "/fake/adb" && $0.serverPort == "15038" })
        XCTAssertEqual(f.adb.endpoint, before.endpoint)
        XCTAssertTrue(f.adb.session().cancellation === before.cancellation)
        XCTAssertFalse(before.cancellation.isCancelled)
    }

    func testValidationWorksWithoutAnActiveEndpointAndStillDoesNotActivate() {
        let f = Fixture()
        XCTAssertNil(f.adb.endpoint)
        XCTAssertTrue(f.adb.validateUSBSelection(serial: serial).isReady)
        XCTAssertNil(f.adb.endpoint)
        XCTAssertEqual(f.argv, healthyTrace)
    }

    func testUSBConnectDisconnectAreNoOpsAndEnsureConnectedUsesFreshValidation() throws {
        let f = Fixture(), usb = try endpoint()
        f.adb.beginSession(endpoint: usb)
        XCTAssertEqual(f.adb.connect(), "")
        XCTAssertTrue(f.calls.isEmpty)
        XCTAssertTrue(f.adb.ensureConnected().ok)
        let previous = f.adb.session()
        f.adb.beginSession(endpoint: nil)
        XCTAssertEqual(f.adb.disconnect(endpoint: usb), "")
        XCTAssertTrue(previous.cancellation.isCancelled)
        XCTAssertNil(f.adb.endpoint)
        XCTAssertEqual(f.argv, healthyTrace)
    }

    func testAuthorizationAndOfflineDoNotProbeOrRecover() {
        for (state, expected) in [("unauthorized", AdbUSBReadiness.awaitingAuthorization), ("offline", .offline)] {
            let f = Fixture(); f.rows = "\(serial) \(state) usb:synthetic-1"
            let result = f.adb.validateUSBSelection(serial: serial)
            XCTAssertEqual(result.readiness, expected)
            XCTAssertFalse(result.isReady)
            XCTAssertEqual(result.endpoint?.serial, serial)
            XCTAssertEqual(result.diagnostic, state)
            XCTAssertEqual(f.argv, [["devices", "-l"]])
        }
    }

    func testUserRetryFreshlyReenumeratesAuthorizationThenProbes() {
        let f = Fixture(); f.rows = "\(serial) unauthorized usb:synthetic-1"
        XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, .awaitingAuthorization)
        f.rows = "\(serial) device usb:synthetic-1"
        XCTAssertTrue(f.adb.validateUSBSelection(serial: serial).isReady)
        XCTAssertEqual(f.argv, [["devices", "-l"]] + healthyTrace)
    }

    func testOldReadyResultDoesNotBypassFreshMissingOrDuplicateCandidate() {
        for rows in ["", "\(serial) device usb:1\n\(serial) future-state"] {
            let f = Fixture()
            let old = f.adb.validateUSBSelection(serial: serial)
            XCTAssertTrue(old.isReady)
            f.adb.beginSession(endpoint: old.endpoint)
            f.rows = rows
            XCTAssertFalse(f.adb.ensureConnected().ok)
            XCTAssertEqual(f.argv, healthyTrace + [["devices", "-l"]])
        }
    }

    func testDuplicateCountsEveryStateAndTransportBeforeAnyTargetQuery() {
        for other in ["device usb:2", "offline usb:2", "unauthorized", "future-state", "device usb:"] {
            let f = Fixture(); f.rows = "\(serial) device usb:1\n\(serial) \(other)"
            let result = f.adb.validateUSBSelection(serial: serial)
            XCTAssertEqual(result.readiness, .ambiguous)
            XCTAssertNil(result.endpoint)
            XCTAssertEqual(f.argv, [["devices", "-l"]])
        }
    }

    func testMissingUnsupportedStateOrTransportNeverProbes() {
        for (rows, expected) in [("other device usb:1", AdbUSBReadiness.missing),
                                 ("\(serial) bootloader usb:1", .unsupported),
                                 ("\(serial) future-state", .unsupported),
                                 ("\(serial) device usb:1 usb:2", .unsupported)] {
            let f = Fixture(); f.rows = rows
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, expected)
            XCTAssertEqual(f.argv, [["devices", "-l"]])
        }
    }

    func testInvalidUserSerialNeverBecomesAnADBTarget() {
        for input in ["", " ", "-s", "a;b", "a\n", "a\u{0}", "a/b", "host:5555", "USB serial", "é"] {
            let f = Fixture()
            XCTAssertEqual(f.adb.validateUSBSelection(serial: input).readiness, .unsupported, input)
            XCTAssertTrue(f.calls.isEmpty)
        }
    }

    func testUnknownCandidateUsesExactlyOneBoundedSelectedDevpathQuery() {
        let f = Fixture()
        f.rows = (0..<255).map { "other\($0) device" }.joined(separator: "\n") + "\n\(serial) device"
        XCTAssertTrue(f.adb.validateUSBSelection(serial: serial).isReady)
        XCTAssertEqual(f.argv, [["devices", "-l"], ["-s", serial, "get-devpath"]] + Array(healthyTrace.dropFirst()))
        XCTAssertEqual(f.calls.map(\.timeout), [3, 3, 3, 25])
    }

    func testUnknownAuthorizationNeedsTypeEvidenceButNeverShell() {
        for (state, expected) in [("unauthorized", AdbUSBReadiness.awaitingAuthorization), ("offline", .offline)] {
            let f = Fixture(); f.rows = "\(serial) \(state)"
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, expected)
            XCTAssertEqual(f.argv, [["devices", "-l"], ["-s", serial, "get-devpath"]])
        }
    }

    func testAbsentOrMalformedDevpathNeverProvesUSBOrDispatchesShell() {
        let outputs = ["unknown\n", "1-2\n", "usb:\n", " usb:1\n", "usb:1 \n", "usb:1\nextra\n", "USB:1\n", "usb:\u{7f}\n"]
        for output in outputs {
            let f = Fixture(); f.rows = "\(serial) device"
            f.response = { $0.arguments.last == "get-devpath" ? ProcessResult(output: output, exitCode: 0) : nil }
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, .unsupported, output)
            XCTAssertEqual(f.argv, [["devices", "-l"], ["-s", serial, "get-devpath"]])
        }
    }

    func testFailedTruncatedOrStderrOnlyDevpathCannotPromoteUnknown() {
        let results: [ProcessResult] = [
            .init(output: "usb:1", exitCode: 1), .init(standardError: "usb:1", exitCode: 0, outcome: .exited),
            .init(standardOutput: "usb:1", exitCode: 0, outcome: .exited, outputTruncated: true),
            .init(standardOutput: "usb:1", exitCode: 0, outcome: .timedOut),
            .init(standardOutput: "usb:1", exitCode: 0, outcome: .signalled(15)),
            .init(standardOutput: "usb:1", exitCode: 0, outcome: .launchFailed(2)),
            .init(standardOutput: "usb:1", exitCode: 0, outcome: .ioFailure(5))
        ]
        for output in results {
            let f = Fixture(); f.rows = "\(serial) device"
            f.response = { $0.arguments.last == "get-devpath" ? output : nil }
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, .unsupported)
            XCTAssertEqual(f.argv, [["devices", "-l"], ["-s", serial, "get-devpath"]])
        }
    }

    func testFailedIncompleteOrDamagedDiscoveryNeverAllowsTargetQueries() {
        let full = list("\(serial) device usb:1")
        let results: [(ProcessResult, AdbUSBReadiness)] = [
            (.init(output: full, exitCode: 1), .discoveryFailed(.commandFailed(1))),
            (.init(standardOutput: full, exitCode: 0, outcome: .timedOut), .discoveryFailed(.timedOut)),
            (.init(standardOutput: full, exitCode: 0, outcome: .exited, outputTruncated: true), .discoveryFailed(.truncated)),
            (.init(output: "List of devices attached\n\(serial) device usb:1\nbroken\n\n", exitCode: 0), .discoveryFailed(.invalidOutput(line: 3)))
        ]
        for (output, expected) in results {
            let f = Fixture(); f.response = { _ in output }
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, expected)
            XCTAssertEqual(f.argv, [["devices", "-l"]])
        }
    }

    func testGetStateAuthorizationDoesNotContinueToProbeOrRecovery() {
        let f = Fixture()
        let diagnostic = "error: device unauthorized. Approve on device"
        f.response = { $0.arguments.last == "get-state" ? .init(standardError: diagnostic, exitCode: 1, outcome: .exited) : nil }
        let result = f.adb.validateUSBSelection(serial: serial)
        XCTAssertEqual(result.readiness, .awaitingAuthorization)
        XCTAssertEqual(result.diagnostic, diagnostic)
        XCTAssertEqual(f.argv, Array(healthyTrace.prefix(2)))
    }

    func testUSBEnsureConnectedFailureNeverUsesTCPOrServerRecovery() throws {
        let f = Fixture(); f.adb.beginSession(endpoint: try endpoint())
        f.response = { $0.arguments.last == "echo __mimonitor_probe__" ? .init(output: "error: device offline", exitCode: 1) : nil }
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertFalse(f.adb.ensureConnected().ok)
        XCTAssertEqual(f.argv, healthyTrace + healthyTrace)
        XCTAssertFalse(f.argv.contains { $0.contains("connect") || $0.contains("disconnect") || $0.contains("host-features") || $0.contains("kill-server") || $0.contains("start-server") })
    }

    func testCancelledChildDoesNotDispatchOrCancelActiveParent() {
        let f = Fixture(); f.adb.ip = "192.0.2.20"
        let parent = f.adb.session(), child = parent.childOperation(); child.cancellation.cancel()
        let result = f.adb.withSession(child) { f.adb.validateUSBSelection(serial: serial) }
        XCTAssertEqual(result.readiness, .cancelled)
        XCTAssertTrue(f.calls.isEmpty)
        XCTAssertFalse(parent.cancellation.isCancelled)
        XCTAssertEqual(f.adb.ip, "192.0.2.20")
    }

    func testCancellationAtEveryStageDiscardsSuccessfulLookingResults() {
        for stage in ["-l", "get-devpath", "get-state", "echo __mimonitor_probe__"] {
            let f = Fixture(); f.rows = "\(serial) device"
            f.response = { request in if request.arguments.last == stage { request.cancellation.cancel() }; return nil }
            let parent = f.adb.session(), child = parent.childOperation()
            let result = f.adb.withSession(child) { f.adb.validateUSBSelection(serial: serial) }
            XCTAssertEqual(result.readiness, .cancelled, stage)
            XCTAssertNil(result.endpoint)
            XCTAssertEqual(f.argv.last?.last, stage)
            XCTAssertFalse(parent.cancellation.isCancelled)
        }
    }

    func testInjectedCancellationAtEveryStageIsReportedAsCancellation() {
        for stage in ["-l", "get-devpath", "get-state", "echo __mimonitor_probe__"] {
            let f = Fixture(); f.rows = "\(serial) device"
            f.response = { $0.arguments.last == stage ? .cancelled : nil }
            XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, .cancelled, stage)
            XCTAssertEqual(f.argv.last?.last, stage)
        }
    }

    func testSameEndpointAndCrossEndpointReplacementCancelOldValidation() {
        for replacement in ["192.0.2.20", "192.0.2.21"] {
            for stage in ["-l", "get-state", "echo __mimonitor_probe__"] {
                let f = Fixture(); f.adb.ip = "192.0.2.20"
                let old = f.adb.session()
                f.response = { request in
                    if request.arguments.last == stage { f.adb.beginSession(ip: replacement) }
                    return nil
                }
                XCTAssertEqual(f.adb.validateUSBSelection(serial: serial).readiness, .cancelled)
                XCTAssertEqual(f.argv.last?.last, stage)
                XCTAssertTrue(old.cancellation.isCancelled)
                XCTAssertEqual(f.adb.ip, replacement)
                XCTAssertFalse(f.adb.session().cancellation.isCancelled)
            }
        }
    }

    func testValidationDoesNotInterleaveWithAnExistingTransaction() {
        let lock = NSLock(); var calls: [[String]] = []
        let adb = AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "15038",
            runtime: { _ in nil }, guardianAPK: { nil })) { request in
                lock.lock(); calls.append(request.arguments); lock.unlock()
                let output = request.arguments.last == "-l" ? "List of devices attached\n000AbC-_9.z device usb:1\n\n"
                    : request.arguments.last == "get-state" ? "device" : "__mimonitor_probe__"
                return ProcessResult(output: output, exitCode: 0)
            }
        adb.ip = "192.0.2.20"
        let began = DispatchSemaphore(value: 0), queued = DispatchSemaphore(value: 0)
        let completed = expectation(description: "Both workers completed"); completed.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            adb.transaction {
                _ = adb.run(["-s", adb.serial, "first"]); began.signal()
                XCTAssertEqual(queued.wait(timeout: .now() + 2), .success)
                _ = adb.run(["-s", adb.serial, "second"])
            }
            completed.fulfill()
        }
        DispatchQueue.global().async {
            XCTAssertEqual(began.wait(timeout: .now() + 2), .success); queued.signal()
            XCTAssertTrue(adb.validateUSBSelection(serial: "000AbC-_9.z").isReady)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        lock.lock(); let recorded = calls; lock.unlock()
        XCTAssertEqual(recorded, [["-s", "192.0.2.20:5555", "first"], ["-s", "192.0.2.20:5555", "second"]] + healthyTrace)
    }
}
