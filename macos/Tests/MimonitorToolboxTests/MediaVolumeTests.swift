import ToolboxDomain
import ToolboxApplication
#if canImport(Cocoa)
import XCTest
@testable import MimonitorToolbox

/// 音量/静音的绝对控制走 `service call audio` 的 binder 通道：
/// transaction code 是 AIDL 常量、返回的 Parcel dump 要手工拆，
/// 解析错的表现是「按键完全没反应」或写到别的音量，所以这里锁住。
final class MediaVolumeTests: XCTestCase {

    // MARK: Parcel 解析

    func testParseVolumeFromParcel() {
        // service call audio 21 i32 3 → volume 24
        let output = "Result: Parcel(\t00000000 00000018   \'........\')"
        XCTAssertEqual(AdbClient.parseServiceCallInt(output), 24)
    }

    func testParseMuteTrueFromParcel() {
        let output = "Result: Parcel(\t00000000 00000001   \'........\')"
        XCTAssertEqual(AdbClient.parseServiceCallInt(output), 1)
    }

    func testParseMaxVolumeFromParcel() {
        let output = "Result: Parcel(\t00000000 00000064   \'........\')"
        XCTAssertEqual(AdbClient.parseServiceCallInt(output), 100)
    }

    func testParseVoidParcelReturnsNil() {
        // void 方法（如 setStreamVolume）只有异常码
        let output = "Result: Parcel(\t00000000    \'....\')"
        XCTAssertNil(AdbClient.parseServiceCallInt(output))
    }

    func testParseErrorParcelReturnsNil() {
        let output = "Result: Parcel(Error: 0xffffffffffffffb6 \"Not a data message\")"
        XCTAssertNil(AdbClient.parseServiceCallInt(output))
    }

    func testParseEmptyOutputReturnsNil() {
        XCTAssertNil(AdbClient.parseServiceCallInt(""))
    }

    // MARK: 调用是否成功

    func testServiceCallSucceededForVoidResult() {
        XCTAssertTrue(AdbClient.serviceCallSucceeded("Result: Parcel(\t00000000    \'....\')"))
    }

    func testServiceCallSucceededForIntResult() {
        XCTAssertTrue(AdbClient.serviceCallSucceeded("Result: Parcel(\t00000000 00000018   \'........\')"))
    }

    func testServiceCallFailedForException() {
        let output = "Result: Parcel( 00000000 ffffffff \'Exception occurred...\')"
        XCTAssertFalse(AdbClient.serviceCallSucceeded(output))
    }

    func testServiceCallFailedForBadTransaction() {
        let output = "Result: Parcel(Error: 0xffffffffffffffb6 \"Not a data message\")"
        XCTAssertFalse(AdbClient.serviceCallSucceeded(output))
    }

    func testServiceCallFailedForEmptyOutput() {
        XCTAssertFalse(AdbClient.serviceCallSucceeded(""))
    }

    // MARK: 音频输出设备匹配

    func testOutputMatchesDisplayPortName() {
        XCTAssertTrue(AudioOutputMonitor.matches(configuredName: "Mi Monitor",
                                                 outputName: "Mi Monitor"))
    }

    func testOutputMatchesEqMacVirtualDevice() {
        // eqMac 转发时设备名会带上后缀，包含匹配要能命中
        XCTAssertTrue(AudioOutputMonitor.matches(configuredName: "Mi Monitor",
                                                 outputName: "Mi Monitor (eqMac)"))
    }

    func testOutputMatchIsCaseInsensitive() {
        XCTAssertTrue(AudioOutputMonitor.matches(configuredName: "mi monitor",
                                                 outputName: "MI MONITOR"))
    }

    func testOutputDoesNotMatchOtherDevice() {
        XCTAssertFalse(AudioOutputMonitor.matches(configuredName: "Mi Monitor",
                                                  outputName: "MacBook Air Speakers"))
    }

    func testOutputUnknownDoesNotMatch() {
        // 读不到设备名时放行给系统，不吞按键
        XCTAssertFalse(AudioOutputMonitor.matches(configuredName: "Mi Monitor", outputName: nil))
        XCTAssertFalse(AudioOutputMonitor.matches(configuredName: "Mi Monitor", outputName: ""))
    }

    func testEmptyConfiguredNameDisablesGate() {
        XCTAssertTrue(AudioOutputMonitor.matches(configuredName: "   ",
                                                 outputName: "MacBook Air Speakers"))
    }
}
#endif
