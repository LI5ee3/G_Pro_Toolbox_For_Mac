import ToolboxDomain
import ToolboxApplication
import XCTest
@testable import MimonitorToolbox

final class ADBVolumeRoutingTests: XCTestCase {
    private func handles(enabled: Bool = true, connected: Bool = true,
                         gate: Bool = true, output: String? = "Mi Monitor") -> Bool {
        AudioOutputMonitor.shouldHandleVolumeKeys(enabled: enabled, adbConnected: connected,
            gateEnabled: gate, configuredOutputName: "Mi Monitor", outputName: output)
    }

    func testDisconnectedADBAlwaysLeavesSystemVolumeKeysAlone() {
        XCTAssertFalse(handles(connected: false))
        XCTAssertFalse(handles(connected: false, gate: false))
    }

    func testDisabledKeysAreNeverIntercepted() {
        XCTAssertFalse(handles(enabled: false, gate: false))
    }

    func testConnectedADBOnlyInterceptsTheConfiguredOutputWhenGated() {
        XCTAssertTrue(handles())
        XCTAssertTrue(handles(output: "Mi Monitor (eqMac)"))
        XCTAssertFalse(handles(output: "AirPods"))
        XCTAssertFalse(handles(output: "REDMI G Pro 32U 2026"))
    }

    func testUnknownOutputIsSafeAndExplicitlyDisablingTheGateStillWorks() {
        XCTAssertFalse(handles(output: nil))
        XCTAssertTrue(handles(gate: false, output: nil))
    }
}
