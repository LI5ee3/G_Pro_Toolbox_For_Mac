import Foundation
import XCTest
import ToolboxDomain
import ToolboxConcurrency
import ToolboxApplication

final class AdbDiscoveryTests: XCTestCase {
    private let header = "List of devices attached\n"

    private func list(_ rows: String) -> String { header + rows + "\n" }

    private func devices(_ output: String, file: StaticString = #filePath, line: UInt = #line) -> [AdbDiscoveredDevice] {
        guard case .complete(let devices) = AdbDeviceListParser.parse(output) else {
            XCTFail("Expected complete list", file: file, line: line)
            return []
        }
        return devices
    }

    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        AdbClient(resources: RuntimeResources(adbPath: "/injected/adb", serverPort: "15038",
            runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
    }

    func testCompleteEmptyListIsDifferentFromMissingOutput() {
        XCTAssertEqual(AdbDeviceListParser.parse(list("")), .complete([]))
        XCTAssertEqual(AdbDeviceListParser.parse(""), .failed(.invalidOutput(line: 1)))
    }

    func testLockedClientMixedFixturePreservesTransportStateAndAmbiguity() {
        // Exact synthetic stdout recorded with locked adb 37.0.1-15733141 against an isolated fake server.
        // Evidence: validation/S2-01-fake-discovery-20261022-222707/locked-adb-discovery.json.
        let output = list("""
        000AbC\tdevice usb:123456X product:fixture model:Fixture_Monitor device:fixture transport_id:1
        192.0.2.10:5555\tdevice product:fixture model:Fixture_Monitor device:fixture transport_id:2
        000NoUsbField\tdevice product:fixture model:Fixture_Monitor device:fixture transport_id:3
        emulator-5554\tdevice product:sdk model:sdk device:generic transport_id:4
        adb-fixture._adb-tls-connect._tcp\tdevice product:fixture model:Fixture_Monitor transport_id:5
        unauthorizedFixture\tunauthorized usb:123457X transport_id:6
        offlineFixture\toffline usb:123458X transport_id:7
        permissionFixture\tno permissions (fixture diagnostic) usb:123459X transport_id:8
        unknownState\tfuture-state vendor_extra:value transport_id:9
        duplicate\tdevice usb:123460X transport_id:10
        duplicate\toffline usb:123461X transport_id:11

        """)
        let found = devices(output)
        XCTAssertEqual(found.count, 11)
        guard found.count == 11 else { return }
        XCTAssertEqual(found[0].serial, "000AbC")
        XCTAssertEqual(found[0].transport, .usb(path: "123456X"))
        XCTAssertEqual(found[1].transport, .tcp(host: "192.0.2.10", port: 5555))
        XCTAssertEqual(found[2].transport, .unknown)
        XCTAssertEqual(found[3].transport, .unsupported)
        XCTAssertEqual(found[4].transport, .unsupported)
        XCTAssertEqual(found[5].state, .unauthorized)
        XCTAssertEqual(found[6].state, .offline)
        XCTAssertEqual(found[7].state, .unsupported("no permissions"))
        XCTAssertTrue(found[7].rawLine.contains("(fixture diagnostic)"))
        XCTAssertEqual(found[8].state, .unknown("future-state"))
        XCTAssertEqual(found.map(\.isSelectable), [true, true, false, false, false, true, true, false, false, false, false])
        XCTAssertEqual(found.map(\.isAmbiguous), [false, false, false, false, false, false, false, false, false, true, true])
    }

    func testOneDeviceRetainsExactSerialAndOrderedUnknownFields() {
        let row = "00AbC-_9.z\tdevice usb:1-2 vendor_extra:first:second vendor_extra:another empty: bare-token"
        let found = devices(list(row))
        XCTAssertEqual(found.first?.serial, "00AbC-_9.z")
        XCTAssertEqual(found.first?.rawLine, row)
        XCTAssertEqual(found.first?.fields.map(\.key), ["usb", "vendor_extra", "vendor_extra", "empty", "bare-token"])
        XCTAssertEqual(found.first?.fields.map(\.value), ["1-2", "first:second", "another", "", nil])
        XCTAssertEqual(found.first?.isSelectable, true)
    }

    func testMissingUsbEvidenceNeverGuessesPhysicalTransport() {
        for serial in ["000AbC", "192.0.2.10", "Monitor.local", "1234567890"] {
            let found = devices(list("\(serial) device model:MiTV transport_id:1"))
            XCTAssertEqual(found.first?.transport, .unknown, serial)
            XCTAssertEqual(found.first?.isSelectable, false, serial)
        }
    }

    func testUnsupportedStatesAndFutureStatesRetainOriginalValues() {
        for state in ["bootloader", "recovery", "sideload", "rescue", "future-v2"] {
            let found = devices(list("000AbC \(state) usb:1-2"))
            XCTAssertEqual(found.first?.state, state == "future-v2" ? .unknown(state) : .unsupported(state))
            XCTAssertEqual(found.first?.isSelectable, false)
        }
    }

    func testDuplicateSerialAcrossDifferentRowsIsNeverSelectable() {
        let found = devices(list("same device usb:1 transport_id:11\nsame unauthorized usb:2 transport_id:12"))
        XCTAssertEqual(found.map(\.isAmbiguous), [true, true])
        XCTAssertEqual(found.map(\.isSelectable), [false, false])
        XCTAssertEqual(found.map(\.serial), ["same", "same"])
    }

    func testTcpHostAndPortAreValidatedWithoutChangingSpelling() {
        for (serial, host, port) in [("192.0.2.10:5555", "192.0.2.10", UInt16(5555)),
                                     ("Monitor-01.Local:1234", "Monitor-01.Local", UInt16(1234)),
                                     ("localhost:65535", "localhost", UInt16(65535))] {
            let found = devices(list("\(serial) device transport_id:1"))
            XCTAssertEqual(found.first?.serial, serial)
            XCTAssertEqual(found.first?.transport, .tcp(host: host, port: port))
            XCTAssertEqual(found.first?.isSelectable, true)
        }
    }

    func testUnsupportedOrConflictingTransportEvidenceCannotSelect() {
        let serials = ["emulator-5554", "adb-Fixture._adb-tls-connect._tcp", "[::1]:5555", "fe80::1%en0",
                       "https://monitor:5555", "999.0.2.1:5555", "host:0", "host:65536", "host:+5",
                       "host:abc", "host:", ":5555", "bad..host:5555", "-host:5555", "host_:5555"]
        for serial in serials {
            let found = devices(list("\(serial) device"))
            XCTAssertEqual(found.first?.transport, .unsupported, serial)
            XCTAssertEqual(found.first?.isSelectable, false, serial)
        }
        for row in ["192.0.2.1:5555 device usb:1", "000AbC device usb:", "000AbC device usb:1 usb:2"] {
            XCTAssertEqual(devices(list(row)).first?.transport, .unsupported, row)
        }
    }

    func testExplicitUsbStillRejectsUnsafeOrUnverifiedSerialSpellings() {
        for serial in ["-s", "x;reboot", "x$(id)", "x`id`", "x|id", "x&", "x'", "x\"", "x/path", "x\\path", "设备"] {
            let found = devices(list("\(serial) device usb:1"))
            XCTAssertEqual(found.first?.serial, serial)
            XCTAssertEqual(found.first?.transport, .unsupported, serial)
            XCTAssertEqual(found.first?.isSelectable, false, serial)
        }
    }

    func testCRLFAndWhitespaceSeparatorsAreAccepted() {
        let found = devices("List of devices attached\r\n\t000AbC   device\tusb:1\r\n\r\n")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.serial, "000AbC")
        XCTAssertEqual(found.first?.transport, .usb(path: "1"))
    }

    func testMalformedFramingAndRowsRejectWholeListInsteadOfReturningPartialCandidates() {
        for output in ["000AbC device usb:1\n", "List of devices attached", "wrong header\n\n",
                       list("000AbC device usb:1\nmissing-state"), list("List of devices attached")] {
            guard case .failed(.invalidOutput) = AdbDeviceListParser.parse(output) else {
                XCTFail("Malformed list succeeded: \(output)"); continue
            }
        }
    }

    func testControlCharactersAndUnicodeLineSeparatorsAreRejected() {
        for value in ["\u{0}", "\u{1B}", "\u{7F}", "\u{85}", "\u{9F}", "\u{2028}", "\u{2029}", "\r"] {
            XCTAssertEqual(AdbDeviceListParser.parse(list("000\(value)AbC device usb:1")), .failed(.invalidOutput(line: 2)))
        }
    }

    func testInputLineAndCandidateLimitsRejectRatherThanTruncate() {
        XCTAssertEqual(AdbDeviceListParser.parse(String(repeating: "x", count: AdbDeviceListParser.maximumBytes + 1)), .failed(.limitExceeded))
        XCTAssertEqual(AdbDeviceListParser.parse(list(String(repeating: "x", count: AdbDeviceListParser.maximumLineBytes + 1))), .failed(.limitExceeded))
        let rows = (0..<AdbDeviceListParser.maximumDevices).map { "serial\($0) device usb:\($0)" }
        XCTAssertEqual(devices(list(rows.joined(separator: "\n"))).count, AdbDeviceListParser.maximumDevices)
        XCTAssertEqual(AdbDeviceListParser.parse(list((rows + ["extra device usb:999"]).joined(separator: "\n"))), .failed(.limitExceeded))
    }

    func testDiscoveryUsesOnlyOneBoundedQueryAndPreservesCurrentSession() {
        var requests: [CommandRequest] = []
        let adb = client { request in
            requests.append(request)
            return ProcessResult(standardOutput: "List of devices attached\n000AbC device usb:1\n\n",
                standardError: "* diagnostic from adb, not a device *\n", exitCode: 0, outcome: .exited)
        }
        adb.ip = "192.0.2.20"
        let before = adb.session()
        let snapshot = adb.discoverDevices()
        guard case .complete(let found) = snapshot.outcome else { return XCTFail("Discovery failed") }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.executable, "/injected/adb")
        XCTAssertEqual(requests.first?.arguments, ["devices", "-l"])
        XCTAssertEqual(requests.first?.serverPort, "15038")
        XCTAssertEqual(requests.first?.timeout, 3)
        XCTAssertTrue(requests.first?.cancellation === before.cancellation)
        XCTAssertEqual(adb.endpoint, before.endpoint)
        XCTAssertTrue(adb.session().cancellation === before.cancellation)
        XCTAssertFalse(before.cancellation.isCancelled)
    }

    func testDiscoveryDoesNotRequireOrSelectAnActiveEndpoint() {
        let adb = client { _ in ProcessResult(output: "List of devices attached\n\n", exitCode: 0) }
        XCTAssertNil(adb.endpoint)
        XCTAssertEqual(adb.discoverDevices().outcome, .complete([]))
        XCTAssertNil(adb.endpoint)
        XCTAssertEqual(adb.serial, "")
    }

    func testEveryProcessFailureRejectsEvenACompleteSuccessfulLookingStdout() {
        let cases: [(ProcessResult.Outcome, Int32, Bool, AdbDiscoveryFailure)] = [
            (.exited, 1, false, .commandFailed(1)), (.timedOut, -1, false, .timedOut),
            (.cancelled, -1, false, .cancelled), (.signalled(15), -15, false, .signalled(15)),
            (.launchFailed(2), -1, false, .launchFailed(2)), (.ioFailure(5), -1, false, .ioFailure(5)),
            (.exited, 0, true, .truncated), (.exited, 1, true, .truncated)
        ]
        for (outcome, code, truncated, expected) in cases {
            let adb = client { _ in ProcessResult(standardOutput: "List of devices attached\n000AbC device usb:1\n\n",
                standardError: "failure diagnostic", exitCode: code, outcome: outcome, outputTruncated: truncated) }
            XCTAssertEqual(adb.discoverDevices().outcome, .failed(expected))
        }
    }

    func testSuccessfulCommandStillRequiresValidStdoutAndDoesNotParseStderr() {
        for output in ["", "List of devices attached\nmissing-state\n\n"] {
            let adb = client { _ in ProcessResult(standardOutput: output,
                standardError: "List of devices attached\n000AbC device usb:1\n\n", exitCode: 0, outcome: .exited) }
            guard case .failed(.invalidOutput) = adb.discoverDevices().outcome else {
                XCTFail("Invalid stdout was replaced by stderr"); continue
            }
        }
    }

    func testCancelledChildDiscoveryDoesNotExecuteOrCancelCurrentSession() {
        let adb = client { _ in XCTFail("Cancelled discovery executed"); return .cancelled }
        let parent = adb.session(), child = parent.childOperation()
        child.cancellation.cancel()
        XCTAssertEqual(adb.withSession(child) { adb.discoverDevices().outcome }, .failed(.cancelled))
        XCTAssertFalse(parent.cancellation.isCancelled)
        XCTAssertTrue(adb.session().cancellation === parent.cancellation)
    }

    func testCancellationDuringDiscoveryDiscardsOtherwiseCompleteResult() {
        let adb = client { request in
            request.cancellation.cancel()
            return ProcessResult(output: "List of devices attached\n\n", exitCode: 0)
        }
        let parent = adb.session(), child = parent.childOperation()
        XCTAssertEqual(adb.withSession(child) { adb.discoverDevices().outcome }, .failed(.cancelled))
        XCTAssertFalse(parent.cancellation.isCancelled)
    }

    func testTargetSwitchDuringDiscoveryCannotPublishOldSuccessOrReplaceNewSession() {
        var adb: AdbClient!
        adb = client { _ in
            adb.beginSession(ip: "192.0.2.21")
            return ProcessResult(output: "List of devices attached\n\n", exitCode: 0)
        }
        adb.ip = "192.0.2.20"
        let before = adb.session()
        XCTAssertEqual(adb.discoverDevices().outcome, .failed(.cancelled))
        XCTAssertTrue(before.cancellation.isCancelled)
        XCTAssertEqual(adb.serial, "192.0.2.21:5555")
        XCTAssertFalse(adb.session().cancellation.isCancelled)
    }

    func testDiscoveryWaitsForExistingTransactionWithoutInterleaving() {
        let lock = NSLock()
        var calls: [[String]] = []
        let adb = client { request in
            lock.lock(); calls.append(request.arguments); lock.unlock()
            return ProcessResult(output: "List of devices attached\n\n", exitCode: 0)
        }
        adb.ip = "192.0.2.20"
        let began = DispatchSemaphore(value: 0), discoveryQueued = DispatchSemaphore(value: 0)
        let completed = expectation(description: "Both workers completed")
        completed.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            adb.transaction {
                _ = adb.run(["-s", adb.serial, "first"])
                began.signal()
                XCTAssertEqual(discoveryQueued.wait(timeout: .now() + 2), .success)
                _ = adb.run(["-s", adb.serial, "second"])
            }
            completed.fulfill()
        }
        DispatchQueue.global().async {
            XCTAssertEqual(began.wait(timeout: .now() + 2), .success)
            discoveryQueued.signal()
            XCTAssertEqual(adb.discoverDevices().outcome, .complete([]))
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        lock.lock(); let recorded = calls; lock.unlock()
        XCTAssertEqual(recorded, [["-s", "192.0.2.20:5555", "first"], ["-s", "192.0.2.20:5555", "second"], ["devices", "-l"]])
    }
}
