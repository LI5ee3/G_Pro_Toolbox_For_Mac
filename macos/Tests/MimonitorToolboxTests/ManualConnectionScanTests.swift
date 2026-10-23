import Foundation
import XCTest
import ToolboxDomain
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor
final class ManualConnectionScanTests: XCTestCase {
    private func scanTrace(_ host: String) -> [String] {
        ["connect \(host):5555", "-s \(host):5555 get-state",
         "-s \(host):5555 shell getprop ro.product.model", "disconnect \(host):5555"]
    }

    func testManualDisconnectThenScanDoesNotReactivateTheUniqueMonitor() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.disconnected)
        runtime.preferences.set(runtime.display.identity, forKey: "saved_ip")
        state.disconnectAdb()
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)

        state.scanNet()
        await state.waitForPendingWork()
        XCTAssertEqual(state.scannedDevices, [runtime.display.identity])
        XCTAssertEqual(state.connectionStatus, .disconnected)
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        XCTAssertNil(state.connection.activeEndpoint)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertEqual(runtime.display.recordedCommands, scanTrace(runtime.display.identity))

        state.monitorAdbServer(refreshState: true)
        state.autoConnectOnStartup()
        state.recoverAfterWake()
        runtime.scheduler.advance(by: 60)
        await state.waitForPendingWork()
        XCTAssertEqual(runtime.display.recordedCommands, scanTrace(runtime.display.identity))
        XCTAssertFalse(state.isConnected)
        state.stop()
    }

    func testModeChoiceThenTCPScanKeepsManualSuppression() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.disconnected)
        state.setConnectionMode(.usb)
        state.setConnectionMode(.tcp)
        let modeGeneration = state.connectionIntent.generation
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        state.scanNet()
        await state.waitForPendingWork()
        XCTAssertGreaterThan(state.connectionIntent.generation, modeGeneration)
        XCTAssertEqual(state.scannedDevices, [runtime.display.identity])
        XCTAssertEqual(state.connectionStatus, .disconnected)
        XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        XCTAssertNil(state.connection.activeEndpoint)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertEqual(runtime.display.recordedCommands, scanTrace(runtime.display.identity))
        state.stop()
    }

    func testInitialAutomaticScanUsesItsVerified5555PortInsteadOfManualInput() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.disconnected)
        state.connection.tcpPortInput = "5566"
        XCTAssertTrue(state.connectionIntent.allowsAutomaticRecovery)
        state.scanNet()
        await state.waitForPendingWork()
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.connection.tcpPortInput, "5555")
        XCTAssertEqual(state.connection.activeEndpoint, .tcp(host: runtime.display.identity))
        XCTAssertEqual(state.adb.endpoint, state.connection.activeEndpoint)
        XCTAssertEqual(Array(runtime.display.recordedCommands.prefix(4)), scanTrace(runtime.display.identity))
        XCTAssertTrue(runtime.display.recordedCommands.contains("-s \(runtime.display.identity):5555 shell echo __mimonitor_probe__"))
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains(":5566") })
        XCTAssertNil(runtime.preferences.object(forKey: "saved_ip"))
        state.stop()
    }

    func testSelectingScannedHostReconnectsSameHostFromCustomPortTo5555() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.connected)
        let custom = AdbEndpoint.tcp(host: runtime.display.identity, port: 5566)
        state.adb.beginSession(endpoint: custom)
        state.connection.activeEndpoint = custom
        state.connection.selectedEndpoint = custom
        state.connection.tcpPortInput = "5566"
        state.scannedDevices = [runtime.display.identity]
        let old = state.adb.session()

        state.selectScannedDevice(runtime.display.identity)
        await state.waitForPendingWork()
        XCTAssertTrue(old.cancellation.isCancelled)
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.connection.tcpPortInput, "5555")
        XCTAssertEqual(state.connection.selectedEndpoint, .tcp(host: runtime.display.identity))
        XCTAssertEqual(state.connection.activeEndpoint, .tcp(host: runtime.display.identity))
        XCTAssertEqual(state.adb.endpoint, state.connection.activeEndpoint)
        XCTAssertTrue(runtime.display.recordedCommands.contains("-s \(runtime.display.identity):5555 get-state"))
        XCTAssertTrue(runtime.display.recordedCommands.contains("-s \(runtime.display.identity):5555 shell echo __mimonitor_probe__"))
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains(":5566") })
        state.stop()
    }

    func testRestrictedUSBMemoryTogglesPreserveBothEnabledAndDisabledLegacyPreferences() async {
        let keys = ["hdr_sdr_local_dimming_enabled", "freesync_mode_memory_enabled", "crosshair_game_mode_only"]
        for original in [false, true] {
            for scenario in [PreviewRuntime.Scenario.usbConnected, .usbUnauthorized, .usbOffline] {
                let runtime = PreviewRuntime()
                for key in keys { runtime.preferences.set(original, forKey: key) }
                runtime.preferences.set(4, forKey: "crosshair_memory")
                runtime.preferences.set(14, forKey: "freesync_previous_mode")
                let dimming = Data("{ \"sdr\": 3, \"hdr\": 2 }".utf8)
                runtime.preferences.set(dimming, forKey: "local_dimming_memory")
                let state = runtime.makeState(scenario)
                XCTAssertTrue(state.connection.identityRestricted)

                state.toggleHdrMemory(!original)
                state.toggleFreesyncMemory(!original)
                state.toggleCrosshairGameModeOnly(!original)
                await state.waitForPendingWork()
                XCTAssertEqual(state.hdrMemoryEnabled, original)
                XCTAssertEqual(state.freesyncMemoryEnabled, original)
                XCTAssertEqual(state.crosshairGameModeOnly, original)
                for key in keys { XCTAssertEqual(runtime.preferences.bool(forKey: key), original, key) }
                XCTAssertEqual(runtime.preferences.integer(forKey: "crosshair_memory"), 4)
                XCTAssertEqual(runtime.preferences.integer(forKey: "freesync_previous_mode"), 14)
                XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), dimming)
                XCTAssertFalse(state.effectiveHdrMemoryEnabled)
                XCTAssertFalse(state.effectiveFreesyncMemoryEnabled)
                XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
                state.stop()
            }
        }
    }
}
