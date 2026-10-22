import XCTest
import Foundation
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

/// Uses only the pre-S1-04 API so the identical fixtures can also run against the parent.
final class TCPCompatibilityTests: XCTestCase {
    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "5038",
            runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
    }

    func testHealthyTCPKeepsArgvOrderTimeoutsAndServerPort() {
        var calls: [CommandRequest] = []
        let adb = client { request in
            calls.append(request)
            let output: String
            switch request.arguments.last {
            case "get-state": output = "device\n"
            case "echo __mimonitor_probe__": output = "__mimonitor_probe__\n"
            case "getprop ro.product.model": output = "MiTV-MFFU1\n"
            default: output = ""
            }
            return ProcessResult(output: output, exitCode: 0)
        }
        adb.beginSession(ip: "Monitor.local")
        _ = adb.connect()
        XCTAssertTrue(adb.ensureConnected().ok)
        XCTAssertEqual(adb.getModel(), "MiTV-MFFU1")
        adb.settingsPut("picture_contrast", "51")
        adb.keyevent("KEYCODE_DPAD_CENTER")
        let previousIP = adb.ip
        adb.beginSession(ip: "")
        _ = adb.disconnect(ip: previousIP)
        XCTAssertEqual(calls.map(\.arguments), [
            ["connect", "Monitor.local:5555"],
            ["-s", "Monitor.local:5555", "get-state"],
            ["-s", "Monitor.local:5555", "shell", "echo __mimonitor_probe__"],
            ["-s", "Monitor.local:5555", "shell", "getprop ro.product.model"],
            ["-s", "Monitor.local:5555", "shell", "settings put global picture_contrast 51"],
            ["-s", "Monitor.local:5555", "shell", "input keyevent KEYCODE_DPAD_CENTER"],
            ["disconnect", "Monitor.local:5555"],
        ])
        XCTAssertEqual(calls.map(\.timeout), [10, 3, 25, 25, 25, 25, 5])
        XCTAssertTrue(calls.allSatisfy { $0.executable == "/fake/adb" && $0.serverPort == "5038" })
        XCTAssertEqual(adb.ip, "")
    }

    func testStaleDeviceStateStillRequiresShellProbeThenReconnect() {
        var calls: [CommandRequest] = [], probes = 0
        let adb = client { request in
            calls.append(request)
            if request.arguments.last == "echo __mimonitor_probe__" {
                probes += 1
                return ProcessResult(output: probes == 1 ? "error: device offline" : "__mimonitor_probe__", exitCode: probes == 1 ? 1 : 0)
            }
            return ProcessResult(output: request.arguments.last == "get-state" ? "device" : "", exitCode: 0)
        }
        adb.ip = "192.0.2.1"
        XCTAssertTrue(adb.ensureConnected().ok)
        XCTAssertEqual(calls.map(\.arguments), [
            ["-s", "192.0.2.1:5555", "get-state"],
            ["-s", "192.0.2.1:5555", "shell", "echo __mimonitor_probe__"],
            ["connect", "192.0.2.1:5555"],
            ["-s", "192.0.2.1:5555", "get-state"],
            ["-s", "192.0.2.1:5555", "shell", "echo __mimonitor_probe__"],
        ])
        XCTAssertEqual(calls.map(\.timeout), [3, 25, 10, 3, 25])
    }

    func testScanPinsTemporaryTargetWithoutReplacingActiveTCP() {
        var calls: [CommandRequest] = []
        let adb = client { request in
            calls.append(request)
            return ProcessResult(output: request.arguments.last == "get-state" ? "device" : "MiTV-MFFU1", exitCode: 0)
        }
        adb.ip = "192.0.2.1"
        XCTAssertEqual(adb.probeScannedDevice(ip: "192.0.2.2")?.ip, "192.0.2.2")
        XCTAssertEqual(adb.ip, "192.0.2.1")
        XCTAssertEqual(calls.map(\.arguments), [
            ["connect", "192.0.2.2:5555"],
            ["-s", "192.0.2.2:5555", "get-state"],
            ["-s", "192.0.2.2:5555", "shell", "getprop ro.product.model"],
            ["disconnect", "192.0.2.2:5555"],
        ])
        XCTAssertEqual(calls.map(\.timeout), [5, 2, 25, 3])
    }
}

@MainActor
final class TCPLegacyConfigurationTests: XCTestCase {
    private func check(_ json: String, valid: Bool) async {
        let runtime = PreviewRuntime(), data = Data(json.utf8)
        runtime.preferences.set(" 192.0.2.7 ", forKey: "saved_ip")
        runtime.preferences.set(data, forKey: "picture_presets_v1")
        let state = AppCoordinator(environment: runtime.environment())
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), " 192.0.2.7 ")
        XCTAssertEqual(state.presetError == nil, valid)
        if valid {
            XCTAssertEqual(state.presetConfiguration.baseline?.deviceIdentity, "192.0.2.7")
            XCTAssertEqual(state.presetConfiguration.baseline?.values["picture_contrast"], "51")
        }
        state.autoConnectOnStartup()
        await state.waitForPendingWork()
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.adb.ip, "192.0.2.7")
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.7")
        XCTAssertEqual(runtime.preferences.data(forKey: "picture_presets_v1"), data)
        XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1"))
        XCTAssertNil(runtime.preferences.object(forKey: "device_registry_v1"))
        XCTAssertTrue(runtime.display.recordedCommands.contains("-s 192.0.2.7:5555 shell echo __mimonitor_probe__"))
        state.stop()
        await state.waitForPendingWork()
    }

    func testExistingJSONBytesAndLegacyIdentitySurviveTCPStartup() async {
        await check("""
        { "presets": [], "tasks": [],
          "baseline": { "deviceIdentity": "192.0.2.7", "values": { "picture_contrast": "51" } } }
        """, valid: true)
    }

    func testMalformedJSONIsRetainedDuringTCPStartup() async {
        await check("{ original damaged configuration", valid: false)
    }
}
