import XCTest
import Foundation
import Synchronization
import ToolboxDomain
import ToolboxApplication
@testable import ToolboxMacAdapters

@MainActor final class DefaultOutputCacheTests: XCTestCase {
    func testConstructionIsInertAndRepeatedReadsNeverQueryCoreAudio() async {
        let reads = Mutex(0)
        var observed = 0, stopped = 0
        let cache = DefaultOutputCache(read: {
            reads.withLock { $0 += 1 }; return AudioOutputSnapshot(uid: "DP-1", name: "Mi Monitor")
        }, observe: { _ in observed += 1; return RuntimeCancellation { stopped += 1 } }, schedule: { _ in RuntimeCancellation() })
        XCTAssertEqual(reads.withLock { $0 }, 0); XCTAssertEqual(observed, 0); XCTAssertNil(cache.snapshot())
        cache.start(); cache.start(); await cache.waitForRefresh()
        for _ in 0..<1000 { XCTAssertEqual(cache.snapshot()?.uid, "DP-1") }
        XCTAssertEqual(reads.withLock { $0 }, 1); XCTAssertEqual(observed, 1)
        cache.stop(); cache.stop(); XCTAssertEqual(stopped, 1); XCTAssertNil(cache.snapshot())
    }
    func testSwitchAndUnknownOutputImmediatelyInvalidateInterceptionGate() async {
        let device = Mutex<AudioOutputSnapshot?>(AudioOutputSnapshot(uid: "A", name: "Mi Monitor"))
        var changed: (@MainActor () -> Void)?
        let cache = DefaultOutputCache(read: { device.withLock { $0 } }, observe: { changed = $0; return RuntimeCancellation() }, schedule: { _ in RuntimeCancellation() })
        cache.start(); await cache.waitForRefresh()
        XCTAssertTrue(AudioOutputMonitor.matches(configuredName: "Mi Monitor", outputName: cache.snapshot()?.name))
        device.withLock { $0 = AudioOutputSnapshot(uid: "B", name: "Headphones") }; changed?()
        XCTAssertNil(cache.snapshot())
        await cache.waitForRefresh(); XCTAssertEqual(cache.snapshot()?.uid, "B")
        XCTAssertFalse(AudioOutputMonitor.matches(configuredName: "Mi Monitor", outputName: cache.snapshot()?.name))
        device.withLock { $0 = nil }; changed?(); await cache.waitForRefresh(); XCTAssertNil(cache.snapshot())
        cache.stop()
    }
    func testStoppedGenerationCannotPublishOrReactivateFromOldCallbacks() async {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        var changed: (@MainActor () -> Void)?
        let reads = Mutex(0)
        let cache = DefaultOutputCache(read: {
            reads.withLock { $0 += 1 }; entered.signal(); _ = release.wait(timeout: .now() + 2)
            return AudioOutputSnapshot(uid: "old", name: "Mi Monitor")
        }, observe: { changed = $0; return RuntimeCancellation() }, schedule: { _ in RuntimeCancellation() })
        cache.start(); XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        cache.stop(); changed?(); release.signal(); await cache.waitForRefresh()
        XCTAssertNil(cache.snapshot()); XCTAssertEqual(reads.withLock { $0 }, 1)
    }
    func testRestartIgnoresOldNotificationGeneration() async {
        var callbacks: [@MainActor () -> Void] = []
        let reads = Mutex(0)
        let cache = DefaultOutputCache(read: {
            reads.withLock { $0 += 1 }; return AudioOutputSnapshot(uid: "A", name: "Mi Monitor")
        }, observe: { callbacks.append($0); return RuntimeCancellation() }, schedule: { _ in RuntimeCancellation() })
        cache.start(); await cache.waitForRefresh(); cache.stop()
        cache.start(); await cache.waitForRefresh()
        callbacks[0]()
        XCTAssertNotNil(cache.snapshot()); XCTAssertEqual(reads.withLock { $0 }, 2)
        cache.stop()
    }
    func testLowFrequencyReconciliationAndTTLHandleLostNotifications() async {
        var time: TimeInterval = 0
        var reconcile: (@MainActor () -> Void)?
        let reads = Mutex(0)
        let cache = DefaultOutputCache(read: {
            reads.withLock { $0 += 1 }; return AudioOutputSnapshot(uid: "A", name: "Mi Monitor")
        }, observe: { _ in RuntimeCancellation() }, schedule: { reconcile = $0; return RuntimeCancellation() }, now: { time })
        cache.start(); await cache.waitForRefresh(); time = 11; XCTAssertNil(cache.snapshot())
        reconcile?(); await cache.waitForRefresh(); XCTAssertNotNil(cache.snapshot())
        XCTAssertEqual(reads.withLock { $0 }, 2)
        cache.stop()
    }
}
