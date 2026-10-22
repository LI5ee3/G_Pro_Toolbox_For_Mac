import AppKit
import SwiftUI
import XCTest
import ToolboxDomain
import ToolboxApplication
import ToolboxConcurrency
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class ManualConnectionPreviewTests: XCTestCase {
    func testOriginalSixScenariosKeepTCPAndExistingReadings() {
        for scenario in [PreviewRuntime.Scenario.connected, .disconnected, .failure, .unknown, .permissionDenied, .loginApproval] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            XCTAssertEqual(state.connection.mode, .tcp)
            XCTAssertFalse(state.connection.identityRestricted)
            XCTAssertEqual(state.connection.ipInput, runtime.display.identity)
            XCTAssertEqual(state.connection.tcpPortInput, "5555")
            XCTAssertEqual(state.connection.isConnected, scenario != .disconnected)
            if scenario != .disconnected {
                XCTAssertEqual(state.connection.activeEndpoint?.serial, "192.0.2.27:5555")
                XCTAssertEqual(state.connection.selectedEndpoint, state.connection.activeEndpoint)
                XCTAssertEqual(state.volume.dashboardVolume, scenario == .unknown ? nil : 10)
            }
            XCTAssertEqual(runtime.display.failWrites, scenario == .failure)
            XCTAssertEqual(runtime.display.unknownReadings, scenario == .unknown)
            state.stop()
        }
    }

    func testReadyUSBScenariosSeedExactActiveEndpointAndIdentityRestriction() {
        for scenario in [PreviewRuntime.Scenario.usbConnected, .dualTransport] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            XCTAssertEqual(state.connection.mode, .usb)
            XCTAssertEqual(state.connection.selectedUSBSerial, "000PreviewUSB")
            XCTAssertEqual(state.connection.activeEndpoint?.serial, "000PreviewUSB")
            XCTAssertEqual(state.connection.selectedEndpoint, state.connection.activeEndpoint)
            XCTAssertEqual(state.adb.endpoint, state.connection.activeEndpoint)
            XCTAssertEqual(state.adb.ip, "")
            XCTAssertTrue(state.connection.isConnected)
            XCTAssertTrue(state.connection.identityRestricted)
            XCTAssertFalse(state.connection.identityNotice.isEmpty)
            XCTAssertEqual(state.connection.transportText, "USB · 000PreviewUSB")
            XCTAssertEqual(state.connection.discoveredDevices.count, scenario == .dualTransport ? 2 : 1)
            XCTAssertTrue(runtime.display.recordedCommands.isEmpty, "Seeding must not connect or initialize")
            state.stop()
        }
    }

    func testAuthorizationAndOfflinePreviewNeverSeedAnActiveSession() {
        for (scenario, readiness) in [(PreviewRuntime.Scenario.usbUnauthorized, AdbUSBReadiness.awaitingAuthorization), (.usbOffline, .offline)] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            XCTAssertEqual(state.connection.mode, .usb)
            XCTAssertEqual(state.connection.selectedEndpoint?.serial, "000PreviewUSB")
            XCTAssertNil(state.connection.activeEndpoint)
            XCTAssertNil(state.adb.endpoint)
            XCTAssertFalse(state.connection.isConnected)
            XCTAssertTrue(state.connection.transportText.contains("未就绪"))
            XCTAssertEqual(state.adb.validateUSBSelection(serial: "000PreviewUSB").readiness, readiness)
            XCTAssertEqual(runtime.display.recordedCommands, ["devices -l"])
            state.stop()
        }
    }

    func testMultipleCandidatesStayUnselectedAndAmbiguityCannotOfferConnection() {
        let runtime = PreviewRuntime(), state = runtime.makeState(.multipleDevices)
        XCTAssertEqual(state.connection.selectedUSBSerial, "")
        XCTAssertNil(state.connection.selectedEndpoint)
        XCTAssertNil(state.connection.activeEndpoint)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertFalse(state.connection.isConnected)
        let candidates = state.connection.discoveredDevices
        XCTAssertEqual(candidates.count, 7)
        let duplicates = candidates.filter { $0.serial == "000PreviewDuplicate" }
        XCTAssertEqual(duplicates.count, 2)
        XCTAssertTrue(duplicates.allSatisfy { !$0.canValidateAsUSB && $0.discoveryTransportText.contains("重复") })
        let unknown = candidates.first { $0.serial == "000PreviewUnknown" }
        XCTAssertEqual(unknown?.usbActionTitle, "验证USB")
        XCTAssertEqual(unknown?.canValidateAsUSB, true)
        XCTAssertEqual(candidates.first { $0.serial == "192.0.2.27:5555" }?.canValidateAsUSB, false)
        XCTAssertEqual(candidates.first { $0.serial == "emulator-5554" }?.canValidateAsUSB, false)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        state.stop()
    }

    func testUnknownPreviewCandidateSupportsOnlyExplicitTargetedUSBValidation() {
        let runtime = PreviewRuntime(), state = runtime.makeState(.multipleDevices)
        XCTAssertTrue(state.adb.validateUSBSelection(serial: "000PreviewUnknown").isReady)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertEqual(runtime.display.recordedCommands, ["devices -l", "-s 000PreviewUnknown get-devpath",
            "-s 000PreviewUnknown get-state", "-s 000PreviewUnknown shell echo __mimonitor_probe__"])
        XCTAssertTrue(runtime.effects.isEmpty)
        state.stop()
    }

    func testFakeUnauthorizedOfflineAndDuplicateTargetsRejectDirectCommands() {
        for scenario in [PreviewRuntime.Scenario.usbUnauthorized, .usbOffline, .multipleDevices] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            let serial = scenario == .multipleDevices ? "000PreviewDuplicate" : "000PreviewUSB"
            let result = runtime.display.execute(CommandRequest(executable: "/mock/adb",
                arguments: ["-s", serial, "shell", "echo __mimonitor_probe__"], serverPort: "0", timeout: 3))
            XCTAssertFalse(result.succeeded)
            XCTAssertFalse(result.standardOutput.contains("__mimonitor_probe__"))
            XCTAssertNil(state.adb.endpoint)
            state.stop()
        }
    }

    func testUSBPresentationDoesNotOfferUnknownStatesOrUnsafeSerials() {
        let output = "List of devices attached\n000Valid device\nx;id device\n000Future future-state usb:1\n000Offline offline usb:2\n\n"
        guard case .complete(let devices) = AdbDeviceListParser.parse(output) else { return XCTFail("fixture failed") }
        XCTAssertEqual(devices.map(\.canValidateAsUSB), [true, false, false, true])
        XCTAssertEqual(devices.map(\.usbActionTitle), ["验证USB", "验证USB", "连接", "连接"])
        XCTAssertEqual(devices[2].discoveryStateText, "未知状态：future-state")
        XCTAssertEqual(devices[3].discoveryStateText, "设备离线")
    }

    func testEveryNewScenarioHomeCanRenderWithOnlyFakeDependencies() {
        for scenario in [PreviewRuntime.Scenario.usbConnected, .usbUnauthorized, .usbOffline, .multipleDevices, .dualTransport] {
            autoreleasepool {
                let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
                let host = NSHostingView(rootView: ToolboxWindowContent(session: ToolboxSession(coordinator: state), screen: .home))
                host.frame = NSRect(x: 0, y: 0, width: 1120, height: 900)
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.width, 0, scenario.rawValue)
                XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
                XCTAssertFalse(runtime.effects.contains("terminal"))
                state.stop()
            }
        }
    }
}
