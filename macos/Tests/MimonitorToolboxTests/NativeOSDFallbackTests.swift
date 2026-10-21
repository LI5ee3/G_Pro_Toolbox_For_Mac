import XCTest
import Foundation
@testable import ToolboxMacAdapters

@MainActor final class NativeOSDFallbackTests: XCTestCase {
    private final class Transport: NativeOSDTransport {
        var messages: [NativeOSDMessage] = []
        var callbacks: [@MainActor () -> Void] = []
        var available = true, synchronousFailure = false
        var resets = 0
        func send(_ message: NativeOSDMessage, failure: @escaping @MainActor () -> Void) -> Bool {
            messages.append(message); callbacks.append(failure)
            if synchronousFailure { failure() }
            return available
        }
        func reset() { resets += 1 }
    }
    private func drain() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    func testConstructionIsInertAndWireImagesDisplayAndSixteenStepsAreRetained() {
        let transport = Transport()
        var displayReads = 0
        let osd = NativeOSD(transport: transport, display: { displayReads += 1; return 27 })
        XCTAssertTrue(transport.messages.isEmpty); XCTAssertEqual(displayReads, 0)
        XCTAssertFalse(osd.showVolume(value: 50) { XCTFail("inactive fallback") })
        osd.start(); osd.start()
        XCTAssertTrue(osd.showBrightness(value: 50) {})
        XCTAssertEqual(transport.messages.last, NativeOSDMessage(image: 1, displayID: 27, filled: 8))
        XCTAssertTrue(osd.showVolume(value: 1000, displayID: 88) {})
        XCTAssertEqual(transport.messages.last, NativeOSDMessage(image: 3, displayID: 88, filled: 16))
        XCTAssertTrue(osd.showVolume(value: 0) {})
        XCTAssertEqual(transport.messages.last?.image, 4)
        XCTAssertTrue(osd.showBrightness(value: -10) {})
        XCTAssertEqual(transport.messages.last?.filled, 0)
        osd.stop()
    }
    func testAsynchronousFailureFallsBackOnceWithLatestValueAndOpensCircuit() async {
        let transport = Transport()
        var time: TimeInterval = 0, values: [Int] = []
        let osd = NativeOSD(transport: transport, now: { time }, display: { 27 })
        osd.start()
        XCTAssertTrue(osd.showVolume(value: 10) { values.append(10) })
        XCTAssertTrue(osd.showVolume(value: 20) { values.append(20) })
        transport.callbacks.last?(); transport.callbacks.last?(); await drain()
        XCTAssertEqual(values, [20])
        XCTAssertFalse(osd.showVolume(value: 30) { values.append(30) })
        XCTAssertEqual(transport.messages.count, 2)
        time = 31; XCTAssertTrue(osd.showVolume(value: 40) { values.append(40) })
        transport.callbacks.last?(); await drain(); XCTAssertEqual(values, [20, 40])
        osd.stop()
    }
    func testOlderRequestAndStoppedLifecycleCannotShowStaleHUD() async {
        let transport = Transport(), osd = NativeOSD(transport: Transport(), display: { 27 })
        osd.stop() // independent inert lifecycle
        var values: [Int] = []
        let active = NativeOSD(transport: transport, display: { 27 }); active.start()
        _ = active.showVolume(value: 10) { values.append(10) }
        let old = transport.callbacks[0]
        _ = active.showVolume(value: 20) { values.append(20) }
        old(); await drain(); XCTAssertTrue(values.isEmpty)
        active.stop(); transport.callbacks.last?(); await drain(); XCTAssertTrue(values.isEmpty)
        active.start(); old(); await drain(); XCTAssertTrue(values.isEmpty)
        XCTAssertTrue(active.showVolume(value: 30) { values.append(30) })
        active.stop()
    }
    func testFailedSubmissionLeavesImmediateFallbackToCallerWithoutDoublePresentation() async {
        let transport = Transport(); transport.available = false; transport.synchronousFailure = true
        var fallbacks = 0
        let osd = NativeOSD(transport: transport, display: { 27 }); osd.start()
        let submitted = osd.showBrightness(value: 50) { fallbacks += 1 }
        if !submitted { fallbacks += 1 } // same immediate fallback used by the coordinator
        await drain(); XCTAssertEqual(fallbacks, 1)
        XCTAssertFalse(osd.showBrightness(value: 60) { fallbacks += 1 })
        osd.stop()
    }
    func testVeryLateFailureDoesNotFlashAnExpiredValue() async {
        let transport = Transport()
        var time: TimeInterval = 0, fallbacks = 0
        let osd = NativeOSD(transport: transport, now: { time }, display: { 27 }); osd.start()
        _ = osd.showMute { fallbacks += 1 }
        time = 2; transport.callbacks.last?(); await drain()
        XCTAssertEqual(fallbacks, 0)
        XCTAssertFalse(osd.showMute { fallbacks += 1 })
        osd.stop()
    }
}
