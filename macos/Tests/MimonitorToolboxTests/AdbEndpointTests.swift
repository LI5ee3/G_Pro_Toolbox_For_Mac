import XCTest
import Foundation
import ToolboxConcurrency
import ToolboxDomain
@testable import ToolboxApplication
@testable import ToolboxMacAdapters
@testable import ToolboxPreviewSupport

final class AdbEndpointTests: XCTestCase {
    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "5038",
            runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
    }

    func testEmptyEndpointCannotDispatchOrFallBackToPresetIdentity() {
        let adb = client { _ in XCTFail("empty destination reached executor"); return ProcessResult(output: "", exitCode: 0) }
        XCTAssertNil(AdbEndpoint.tcp(host: ""))
        XCTAssertNil(AdbEndpoint.tcp(host: "192.0.2.1", port: 0))
        adb.beginSession(endpoint: nil)
        XCTAssertEqual(adb.connect(), "")
        XCTAssertFalse(adb.ensureConnected().ok)
        XCTAssertEqual(adb.deviceState(), "unknown")
        XCTAssertEqual(adb.shell("input keyevent KEYCODE_POWER"), "未连接显示器")
        XCTAssertEqual(adb.disconnect(endpoint: nil), "")
        let device = AdbPresetDevice(adb: adb, endpoint: nil, identity: "192.0.2.1")
        XCTAssertThrowsError(try device.capture())
        XCTAssertThrowsError(try device.apply(["picture_contrast": "51"]))
    }

    func testEndpointPortIsIndependentOfADBServerAndLegacyIdentity() {
        var calls: [CommandRequest] = []
        let adb = client { request in
            calls.append(request)
            return ProcessResult(output: "error: intentional fixture failure", exitCode: 1)
        }
        adb.beginSession(endpoint: AdbEndpoint.tcp(host: "Monitor.local", port: 5566))
        _ = adb.connect()
        let device = AdbPresetDevice(adb: adb, endpoint: adb.session().endpoint, identity: "legacy-owner")
        XCTAssertEqual(device.identity, "legacy-owner")
        XCTAssertThrowsError(try device.capture())
        XCTAssertEqual(calls.map(\.arguments), [
            ["connect", "Monitor.local:5566"],
            ["-s", "Monitor.local:5566", "shell", "settings list global"],
        ])
        XCTAssertTrue(calls.allSatisfy { $0.serverPort == "5038" })
    }

    func testSameEndpointReconnectCancelsParentAndChildButNotNewSession() {
        var calls: [[String]] = []
        let adb = client { request in calls.append(request.arguments); return ProcessResult(output: "device", exitCode: 0) }
        let endpoint = AdbEndpoint.tcp(host: "192.0.2.1")
        adb.beginSession(endpoint: endpoint)
        let parent = adb.session(), child = parent.childOperation()
        adb.beginSession(endpoint: endpoint)
        XCTAssertTrue(parent.cancellation.isCancelled)
        XCTAssertTrue(child.cancellation.isCancelled)
        XCTAssertEqual(child.endpoint, endpoint)
        let stale = adb.withSession(child) { adb.run(["-s", adb.serial, "get-state"]) }
        XCTAssertEqual(stale.outcome, .cancelled)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(adb.session().cancellation.isCancelled)
        XCTAssertEqual(adb.deviceState(), "device")
        XCTAssertEqual(calls, [["-s", "192.0.2.1:5555", "get-state"]])
    }

    func testLegacyIPAssignmentKeepsSameSessionAndCancelsOnChange() {
        let adb = client { _ in XCTFail("assignment dispatched command"); return .cancelled }
        adb.ip = "192.0.2.1"
        let original = adb.session()
        adb.ip = "192.0.2.1"
        XCTAssertFalse(original.cancellation.isCancelled)
        adb.ip = "192.0.2.2"
        XCTAssertTrue(original.cancellation.isCancelled)
        XCTAssertEqual(original.endpoint?.serial, "192.0.2.1:5555")
        XCTAssertEqual(adb.endpoint?.serial, "192.0.2.2:5555")
        adb.ip = ""
        XCTAssertNil(adb.endpoint)
    }

    func testPresetSwitchAfterFirstWriteCancelsRemainingCommandsWithoutRedirect() {
        var calls: [[String]] = []
        var adb: AdbClient!
        adb = client { request in
            calls.append(request.arguments)
            if request.arguments.last == "settings get global mitv.tvplayer.hdmi.last.source" {
                return ProcessResult(output: "23", exitCode: 0)
            }
            adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.2"))
            return ProcessResult(output: "", exitCode: 0)
        }
        adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.1"))
        let submitted = adb.session().childOperation()
        let device = AdbPresetDevice(adb: adb, endpoint: submitted.endpoint, identity: "192.0.2.1")
        XCTAssertThrowsError(try adb.withSession(submitted) {
            try device.apply(["picture_brightness": "50", "picture_contrast": "51"])
        })
        XCTAssertEqual(calls, [
            ["-s", "192.0.2.1:5555", "shell", "settings get global mitv.tvplayer.hdmi.last.source"],
            ["-s", "192.0.2.1:5555", "shell", "settings put global picture_brightness 50"],
        ])
        XCTAssertTrue(submitted.cancellation.isCancelled)
        XCTAssertEqual(adb.endpoint?.serial, "192.0.2.2:5555")
        XCTAssertFalse(adb.session().cancellation.isCancelled)
    }
}

@MainActor
final class PresetEndpointSubmissionTests: XCTestCase {
    func testPresetFactoryReceivesSubmittedEndpointAndUnchangedLegacyIdentity() async {
        let runtime = PreviewRuntime(), base = runtime.environment()
        let received = expectation(description: "preset factory")
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: base.adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, presetDevice: { adb, endpoint, identity in
                XCTAssertEqual(endpoint?.serial, "192.0.2.1:5555")
                XCTAssertEqual(identity, "192.0.2.1")
                XCTAssertEqual(endpoint, adb.operationSession?.endpoint)
                // Changing the live client here must invalidate this operation, not redirect it.
                adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.2"))
                received.fulfill()
                return AdbPresetDevice(adb: adb, endpoint: endpoint, identity: identity)
            }))
        state.adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.1"))
        state.connectionStatus = .connected("fixture")
        // Confirmed fake ownership; this test checks the unchanged device protocol.
        state.connection.identityRestricted = false
        state.connection.presetIdentityKey = "192.0.2.1"
        state.createPreset(name: "cancelled capture")
        await fulfillment(of: [received], timeout: 2)
        await state.waitForPendingWork()
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        XCTAssertTrue(state.presetConfiguration.presets.isEmpty)
        XCTAssertFalse(state.presets.isPresetOperationInFlight)
        XCTAssertFalse(state.presets.isPresetBusy)
        state.stop()
    }
}
