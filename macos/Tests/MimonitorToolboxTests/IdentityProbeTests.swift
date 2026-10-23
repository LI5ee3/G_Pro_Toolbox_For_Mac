import Foundation
import XCTest
import ToolboxDomain
import ToolboxConcurrency
@testable import ToolboxApplication

final class IdentityProbeTests: XCTestCase {
    private let sampledAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private var tcp: AdbEndpoint { AdbEndpoint.tcp(host: "192.0.2.20")! }

    private func parse(_ serial: String, _ boot: String = "") -> IdentityProbeResult {
        DeviceIdentityParser.resolve(roSerialno: serial, roBootSerialno: boot, endpoint: tcp,
            sessionID: sessionID, sampledAt: sampledAt)
    }

    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        AdbClient(resources: RuntimeResources(adbPath: "/injected/adb", serverPort: "15038",
            runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
    }

    private func usb() throws -> AdbEndpoint {
        guard case .complete(let devices) = AdbDeviceListParser.parse("List of devices attached\n000TransportUSB device usb:1\n\n") else {
            throw NSError(domain: "invalid fixture", code: 1)
        }
        return try XCTUnwrap(AdbEndpoint.usb(discovered: XCTUnwrap(devices.first)))
    }

    func testMatchingPropertiesPreserveSpellingAndEvidenceScope() {
        guard case .identified(let evidence) = parse("000AbC-_9.z\r\n", "000AbC-_9.z\n") else { return XCTFail("No evidence") }
        XCTAssertEqual(evidence.stableIdentifier, "000AbC-_9.z")
        XCTAssertEqual(evidence.roSerialno, "000AbC-_9.z")
        XCTAssertEqual(evidence.roBootSerialno, "000AbC-_9.z")
        XCTAssertEqual(evidence.endpoint, tcp)
        XCTAssertEqual(evidence.sessionID, sessionID)
        XCTAssertEqual(evidence.sampledAt, sampledAt)
        XCTAssertEqual(evidence.policyVersion, 1)
    }

    func testOneUsablePropertyAndExplicitAbsentOtherRemainEvidence() {
        for absent in ["", "\n", "\r\n", "unknown\n", "NULL", "00000000", "FFFFFFFF"] {
            for primary in [true, false] {
                let result = primary ? parse("Physical001", absent) : parse(absent, "Physical001")
                guard case .identified(let evidence) = result else { XCTFail("Failed fallback: \(absent)"); continue }
                XCTAssertEqual(evidence.stableIdentifier, "Physical001")
                XCTAssertEqual(evidence.roSerialno, primary ? "Physical001" : nil)
                XCTAssertEqual(evidence.roBootSerialno, primary ? nil : "Physical001")
            }
        }
        guard case .identified(let crlfEvidence) = parse("Physical001\r\n") else { return XCTFail("CRLF fallback failed") }
        XCTAssertEqual(crlfEvidence.stableIdentifier, "Physical001")
    }

    func testPersistedPropertyHelperReusesStrictValidationWithoutTrustingStoredEvidence() {
        XCTAssertEqual(DeviceIdentityParser.stableIdentifier(roSerialno: "000AbC", roBootSerialno: "000AbC"), "000AbC")
        XCTAssertEqual(DeviceIdentityParser.stableIdentifier(roSerialno: nil, roBootSerialno: "Physical001"), "Physical001")
        XCTAssertNil(DeviceIdentityParser.stableIdentifier(roSerialno: "unknown", roBootSerialno: nil))
        XCTAssertNil(DeviceIdentityParser.stableIdentifier(roSerialno: "Physical001", roBootSerialno: "Physical002"))
        XCTAssertNil(DeviceIdentityParser.stableIdentifier(roSerialno: "Physical001", roBootSerialno: "bad\nvalue"))
        XCTAssertNil(DeviceIdentityParser.stableIdentifier(roSerialno: nil, roBootSerialno: nil))
    }

    func testPlaceholdersCannotClaimIdentity() {
        for placeholder in ["", "unknown", "UNKNOWN", "null", "(null)", "none", "n/a", "default", "unset", "serial", "serialno", "0", "000000000000", "ffffffff"] {
            guard case .unknown = parse(placeholder, placeholder) else { XCTFail("Placeholder identified: \(placeholder)"); continue }
        }
    }

    func testMalformedValueCannotBeHiddenByAValidOtherProperty() {
        let invalid = [" leading", "trailing ", "two words", "a\tb", "a\nb", "a\n\n", "a\r", "a\u{0}",
                       "a\u{7f}", "a\u{85}", "a\u{2028}", "设备", String(repeating: "a", count: 257)]
        for value in invalid {
            for result in [parse(value, "Physical001"), parse("Physical001", value)] {
                guard case .unknown = result else { XCTFail("Malformed property became evidence: \(value)"); continue }
            }
        }
        guard case .identified = parse(String(repeating: "a", count: 256)) else { return XCTFail("Boundary value rejected") }
    }

    func testDifferentMeaningfulPropertiesAreConflictIncludingCaseChanges() {
        for pair in [("Physical001", "Physical002"), ("000AbC", "000ABC"), ("00123", "123")] {
            guard case .conflict(let reason) = parse(pair.0, pair.1) else { XCTFail("Disagreement was accepted"); continue }
            XCTAssertTrue(reason.contains("ro.serialno=" + pair.0))
            XCTAssertTrue(reason.contains("ro.boot.serialno=" + pair.1))
        }
    }

    func testProbeUsesExactReadOnlyTargetAndIgnoresStderrAsIdentity() throws {
        let target = try usb()
        var calls: [CommandRequest] = []
        let adb = client { request in
            calls.append(request)
            return ProcessResult(standardOutput: "Physical001\n", standardError: "diagnostic", exitCode: 0, outcome: .exited)
        }
        adb.beginSession(endpoint: tcp)
        let before = adb.session()
        let result = adb.probeIdentity(endpoint: target, sessionID: before.sessionID, sampledAt: sampledAt)
        guard case .identified(let evidence) = result else { return XCTFail("Probe failed") }
        XCTAssertEqual(evidence.endpoint, target)
        XCTAssertEqual(evidence.stableIdentifier, "Physical001")
        XCTAssertNotEqual(evidence.stableIdentifier, target.serial, "USB serial is transport evidence only")
        XCTAssertEqual(calls.map(\.arguments), [["-s", "000TransportUSB", "shell", "getprop ro.serialno"],
            ["-s", "000TransportUSB", "shell", "getprop ro.boot.serialno"]])
        XCTAssertEqual(calls.map(\.timeout), [3, 3])
        XCTAssertTrue(calls.allSatisfy { $0.executable == "/injected/adb" && $0.serverPort == "15038" })
        XCTAssertTrue(calls.allSatisfy { $0.cancellation === before.cancellation })
        XCTAssertEqual(adb.endpoint, before.endpoint)
        XCTAssertEqual(adb.session().sessionID, before.sessionID)
        XCTAssertFalse(before.cancellation.isCancelled)
    }

    func testUnactivatedUSBProbeDoesNotCreateASelectedSession() throws {
        let target = try usb()
        let adb = client { _ in ProcessResult(output: "Physical001", exitCode: 0) }
        let before = adb.session()
        guard case .identified(let evidence) = adb.probeIdentity(endpoint: target, sessionID: before.sessionID, sampledAt: sampledAt) else {
            return XCTFail("Explicit unactivated endpoint failed")
        }
        XCTAssertNil(adb.endpoint)
        XCTAssertEqual(evidence.endpoint, target)
        XCTAssertEqual(evidence.sessionID, before.sessionID)
    }

    func testEveryProcessFailureRejectsOtherwiseValidIdentityAtEitherStage() {
        let failures: [ProcessResult] = [
            .init(output: "Physical001", exitCode: 1),
            .init(standardOutput: "Physical001", exitCode: 0, outcome: .timedOut),
            .init(standardOutput: "Physical001", exitCode: 0, outcome: .signalled(15)),
            .init(standardOutput: "Physical001", exitCode: 0, outcome: .launchFailed(2)),
            .init(standardOutput: "Physical001", exitCode: 0, outcome: .ioFailure(5)),
            .init(standardOutput: "Physical001", exitCode: 0, outcome: .exited, outputTruncated: true)
        ]
        for failure in failures {
            for stage in [1, 2] {
                var calls = 0
                let adb = client { _ in calls += 1; return calls == stage ? failure : .init(output: "Physical001", exitCode: 0) }
                guard case .unknown = adb.probeIdentity(endpoint: tcp, sessionID: adb.session().sessionID, sampledAt: sampledAt) else {
                    XCTFail("Failed property became evidence"); continue
                }
                XCTAssertEqual(calls, stage)
            }
        }
    }

    func testStderrOnlyNeverBecomesIdentityAndValidPairConflictsThroughProductionAPI() {
        let stderrOnly = client { _ in ProcessResult(standardError: "Physical001", exitCode: 0, outcome: .exited) }
        guard case .unknown = stderrOnly.probeIdentity(endpoint: tcp, sessionID: stderrOnly.session().sessionID, sampledAt: sampledAt) else {
            return XCTFail("stderr claimed identity")
        }
        let conflicting = client { request in .init(output: request.arguments.last == "getprop ro.serialno" ? "Physical001" : "Physical002", exitCode: 0) }
        guard case .conflict = conflicting.probeIdentity(endpoint: tcp, sessionID: conflicting.session().sessionID, sampledAt: sampledAt) else {
            return XCTFail("production probe missed conflict")
        }
    }

    func testWrongSessionIDAndCancelledChildDoNotDispatch() {
        let adb = client { _ in XCTFail("Stale identity probe dispatched"); return .cancelled }
        XCTAssertEqual(adb.probeIdentity(endpoint: tcp, sessionID: UUID(), sampledAt: sampledAt), .cancelled)
        let parent = adb.session(), child = parent.childOperation()
        child.cancellation.cancel()
        XCTAssertEqual(adb.withSession(child) { adb.probeIdentity(endpoint: tcp, sessionID: parent.sessionID, sampledAt: sampledAt) }, .cancelled)
        XCTAssertFalse(parent.cancellation.isCancelled)
    }

    func testActualAndInjectedCancellationAtEachPropertyStopTheProbe() {
        for stage in [1, 2] {
            for injected in [true, false] {
                var calls = 0
                let adb = client { request in
                    calls += 1
                    if calls == stage {
                        if injected { return .cancelled }
                        request.cancellation.cancel()
                    }
                    return .init(output: "Physical001", exitCode: 0)
                }
                let parent = adb.session(), child = parent.childOperation()
                XCTAssertEqual(adb.withSession(child) { adb.probeIdentity(endpoint: tcp, sessionID: child.sessionID, sampledAt: sampledAt) }, .cancelled)
                XCTAssertEqual(calls, stage)
                XCTAssertFalse(parent.cancellation.isCancelled)
            }
        }
    }

    func testSameAddressReconnectAndTargetSwitchDiscardOldIdentity() {
        for replacement in ["192.0.2.20", "192.0.2.21"] {
            for stage in [1, 2] {
                var adb: AdbClient!, calls = 0
                adb = client { _ in
                    calls += 1
                    if calls == stage { adb.beginSession(ip: replacement) }
                    return .init(output: "Physical001", exitCode: 0)
                }
                adb.beginSession(endpoint: tcp)
                let before = adb.session()
                XCTAssertEqual(adb.probeIdentity(endpoint: tcp, sessionID: before.sessionID, sampledAt: sampledAt), .cancelled)
                XCTAssertEqual(calls, stage)
                XCTAssertTrue(before.cancellation.isCancelled)
                XCTAssertNotEqual(adb.session().sessionID, before.sessionID)
                XCTAssertEqual(adb.ip, replacement)
            }
        }
    }

    func testSessionIDsFollowExistingCancellationBoundariesAndChildrenInherit() {
        let adb = client { _ in .init(output: "", exitCode: 0) }
        let initial = adb.session()
        XCTAssertEqual(initial.childOperation().sessionID, initial.sessionID)
        adb.resumeSession()
        XCTAssertEqual(adb.session().sessionID, initial.sessionID)
        adb.endpoint = tcp
        let selected = adb.session()
        XCTAssertNotEqual(selected.sessionID, initial.sessionID)
        adb.endpoint = tcp
        XCTAssertEqual(adb.session().sessionID, selected.sessionID)
        adb.beginSession(endpoint: tcp)
        let reconnect = adb.session()
        XCTAssertNotEqual(reconnect.sessionID, selected.sessionID)
        adb.cancelSession()
        XCTAssertEqual(adb.session().sessionID, reconnect.sessionID)
        adb.resumeSession()
        XCTAssertNotEqual(adb.session().sessionID, reconnect.sessionID)
        XCTAssertFalse(adb.session().cancellation.isCancelled)
    }

    func testIdentityPairRemainsInsideOneTransaction() {
        let lock = NSLock(), propertyRead = DispatchSemaphore(value: 0), contenderQueued = DispatchSemaphore(value: 0)
        var calls: [[String]] = []
        let adb = client { request in
            lock.lock(); calls.append(request.arguments); lock.unlock()
            if request.arguments.last == "getprop ro.serialno" {
                propertyRead.signal()
                XCTAssertEqual(contenderQueued.wait(timeout: .now() + 2), .success)
            }
            return .init(output: "Physical001", exitCode: 0)
        }
        adb.endpoint = tcp
        let captured = adb.session(), target = tcp, time = sampledAt
        let done = expectation(description: "Both workers finished"); done.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            guard case .identified = adb.probeIdentity(endpoint: target, sessionID: captured.sessionID, sampledAt: time) else {
                XCTFail("probe failed"); done.fulfill(); return
            }
            done.fulfill()
        }
        DispatchQueue.global().async {
            XCTAssertEqual(propertyRead.wait(timeout: .now() + 2), .success)
            contenderQueued.signal()
            _ = adb.run(["-s", captured.serial, "contender"])
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        lock.lock(); let recorded = calls; lock.unlock()
        XCTAssertEqual(recorded, [["-s", "192.0.2.20:5555", "shell", "getprop ro.serialno"],
            ["-s", "192.0.2.20:5555", "shell", "getprop ro.boot.serialno"], ["-s", "192.0.2.20:5555", "contender"]])
    }
}
