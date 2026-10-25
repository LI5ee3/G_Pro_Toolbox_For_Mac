import XCTest
import ToolboxDomain
import ToolboxApplication
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class ManualConnectionPreviewTests: XCTestCase {
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

    func testUSBPresentationDoesNotOfferUnknownStatesOrUnsafeSerials() {
        let output = "List of devices attached\n000Valid device\nx;id device\n000Future future-state usb:1\n000Offline offline usb:2\n\n"
        guard case .complete(let devices) = AdbDeviceListParser.parse(output) else { return XCTFail("fixture failed") }
        XCTAssertEqual(devices.map(\.canValidateAsUSB), [true, false, false, true])
        XCTAssertEqual(devices.map(\.usbActionTitle), ["验证USB", "验证USB", "连接", "连接"])
        XCTAssertEqual(devices[2].discoveryStateText, "未知状态：future-state")
        XCTAssertEqual(devices[3].discoveryStateText, "设备离线")
    }
}
