import Foundation
import XCTest
import ToolboxDomain
import MimonitorPresetCore
@testable import ToolboxApplication
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class ConnectionDraftTests: XCTestCase {
    func testBrowsingAndDiagnosingDraftPreserveTheActiveTCPOrUSBSession() async {
        for scenario in [PreviewRuntime.Scenario.connected, .usbConnected] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            let session = state.adb.session(), mode = state.connection.mode
            let input = state.ipInput, port = state.connection.tcpPortInput
            let selected = state.connection.selectedUSBSerial
            var draft = ConnectionDraft(connection: state.connection)
            draft.mode = mode == .tcp ? .usb : .tcp
            draft.host = "198.51.100.42"; draft.port = "5566"; draft.usbSerial = "000PreviewOther"
            state.refreshDevices(); await state.waitForPendingWork()
            let commands = runtime.display.recordedCommands
            draft.diagnose(using: state); await state.waitForPendingWork()

            XCTAssertTrue(state.logs.lines.contains { $0.contains("诊断填写的 TCP 地址：198.51.100.42:5566") })
            XCTAssertEqual(runtime.display.recordedCommands, commands)
            XCTAssertEqual(state.adb.session().sessionID, session.sessionID)
            XCTAssertEqual(state.connection.activeEndpoint, session.endpoint)
            XCTAssertFalse(session.cancellation.isCancelled)
            XCTAssertEqual(state.connection.mode, mode)
            XCTAssertEqual(state.ipInput, input); XCTAssertEqual(state.connection.tcpPortInput, port)
            XCTAssertEqual(state.connection.selectedUSBSerial, selected)
            XCTAssertTrue(state.isConnected)
            state.stop()
        }
    }

    func testOnlyExplicitConnectSubmitsTheSelectedUSBTargetOnce() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        runtime.display.configureDiscovery(rows: "000PreviewUSB device usb:preview-1 model:MiTV_Preview")
        state.refreshDevices(); await state.waitForPendingWork()
        let session = state.adb.session(), generation = state.connectionIntent.generation
        var draft = ConnectionDraft(connection: state.connection)
        draft.mode = .usb; draft.usbSerial = "000PreviewUSB"
        XCTAssertTrue(draft.canConnect(state.connection))
        state.refreshDevices()
        XCTAssertFalse(draft.canConnect(state.connection))
        await state.waitForPendingWork()
        XCTAssertTrue(draft.canConnect(state.connection))
        XCTAssertEqual(state.adb.session().sessionID, session.sessionID)
        draft.connect(using: state); await state.waitForPendingWork()
        XCTAssertTrue(session.cancellation.isCancelled)
        XCTAssertEqual(state.connection.mode, .usb)
        XCTAssertEqual(state.connection.activeEndpoint?.serial, "000PreviewUSB")
        XCTAssertEqual(state.connectionIntent.generation, generation + 2)
        XCTAssertEqual(runtime.display.recordedCommands.filter {
            $0 == "-s 000PreviewUSB shell echo __mimonitor_probe__"
        }.count, 1)
        state.stop()
    }

    func testSaveUsesActiveEndpointAndPublishesBusySuccessAndStaleFailure() async throws {
        for scenario in [PreviewRuntime.Scenario.connected, .usbConnected] {
            let runtime = PreviewRuntime(), state = runtime.makeState(scenario)
            let session = state.adb.session(), endpoint = state.connection.activeEndpoint
            state.ipInput = "198.51.100.42"; state.connection.tcpPortInput = "5566"
            let candidate = AdbEndpoint.tcp(host: "198.51.100.42", port: 5566)
            state.connection.selectedEndpoint = candidate
            state.connection.profileMessage = "上一轮结果"
            ConnectionDraft.saveCurrentPreference(using: state)
            XCTAssertTrue(state.connection.identityOperationBusy)
            await state.waitForPendingWork()
            XCTAssertFalse(state.connection.identityOperationBusy)
            XCTAssertTrue(state.connection.profileMessage.contains("已保存"))
            XCTAssertEqual(state.presetWorker.connectionProfileSnapshot().profile?.selectedEndpoint,
                           endpoint.map { ConnectionEndpointReference(endpoint: $0) })
            XCTAssertEqual(state.ipInput, "198.51.100.42"); XCTAssertEqual(state.connection.tcpPortInput, "5566")
            XCTAssertEqual(state.connection.selectedEndpoint, candidate)
            let saved = runtime.preferences.data(forKey: "connection_profile_v1")
            // A real external snapshot change exercises the existing stale-snapshot rejection.
            runtime.preferences.set(try JSONEncoder().encode(PresetConfiguration()), forKey: "picture_presets_v1")
            ConnectionDraft.saveCurrentPreference(using: state)
            XCTAssertTrue(state.connection.identityOperationBusy)
            await state.waitForPendingWork()
            XCTAssertFalse(state.connection.identityOperationBusy)
            XCTAssertTrue(state.connection.profileMessage.contains("未提交"))
            XCTAssertTrue(state.connection.profileMessage.contains("重新查看"))
            XCTAssertEqual(runtime.preferences.data(forKey: "connection_profile_v1"), saved)
            XCTAssertEqual(state.adb.session().sessionID, session.sessionID)
            XCTAssertFalse(session.cancellation.isCancelled)
            XCTAssertEqual(state.connection.activeEndpoint, endpoint)
            state.stop()
        }
    }
}
