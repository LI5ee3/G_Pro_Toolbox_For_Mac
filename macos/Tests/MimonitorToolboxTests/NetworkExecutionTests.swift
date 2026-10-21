import Foundation
import XCTest
import Synchronization
import ToolboxConcurrency
@testable import ToolboxMacAdapters

final class NetworkExecutionTests: XCTestCase {
    func testSubnetFiltersRetainExistingLANRulesAndOrdering() {
        let sample = """
        lo0: flags=0
            inet 127.0.0.1 netmask 0
        en0: flags=0
            inet 192.168.1.20 netmask 0
            inet 192.168.1.21 netmask 0
        en1: flags=0
            inet 10.0.1.20 netmask 0
        utun3: flags=0
            inet 192.168.20.1 netmask 0
        en2: flags=0
            inet 169.254.1.2 netmask 0
            inet 198.18.0.1 netmask 0
            inet 198.19.0.1 netmask 0
            inet 10.20.1.2 --> 10.20.1.2 netmask 0
        """
        XCTAssertEqual(NetworkScan.parseSubnets(sample), ["192.168.1", "10.0.1"])
    }
    func testIfconfigAndPingUseBoundedInjectedRunnerAndRejectPartialFailure() {
        let token = CommandCancellation()
        XCTAssertEqual(NetworkScan.localIPv4Subnets(cancellation: token, execute: { request in
            XCTAssertEqual(request.executable, "/sbin/ifconfig"); XCTAssertEqual(request.timeout, 3)
            XCTAssertTrue(request.cancellation === token)
            return ProcessResult(standardOutput: "en0: flags=0\n inet 192.168.1.2 netmask 0", exitCode: -1, outcome: .timedOut)
        }), [])
        XCTAssertFalse(NetworkScan.ping(host: "192.0.2.1", cancellation: token, execute: { request in
            XCTAssertEqual(request.arguments, ["-c", "1", "-W", "1000", "192.0.2.1"])
            XCTAssertEqual(request.timeout, 2); XCTAssertTrue(request.cancellation === token)
            return .cancelled
        }))
    }
    func testScanKeepsFourSubnetLimitAndNumericSortingWithoutOpeningSockets() {
        let calls = Mutex<[String]>([])
        let results = NetworkScan.scan(maxConcurrent: 4, subnets: ["192.0.2", "198.51.100", "203.0.113", "10.1.1", "10.2.2"]) { ip, port, _, _ in
            XCTAssertEqual(port, 5555)
            calls.withLock { $0.append(ip) }
            return ip == "192.0.2.10" || ip == "192.0.2.2"
        }
        XCTAssertEqual(results, ["192.0.2.2", "192.0.2.10"])
        XCTAssertEqual(calls.withLock { $0.count }, 4 * 254)
        XCTAssertFalse(calls.withLock { $0.contains { $0.hasPrefix("10.2.2.") } })
    }
    func testScanCancellationStopsSchedulingAndReturnsPromptly() {
        let token = CommandCancellation(), count = Mutex(0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { token.cancel() }
        let start = Date()
        _ = NetworkScan.scan(maxConcurrent: 2, cancellation: token, subnets: ["192.0.2"]) { _, _, _, child in
            count.withLock { $0 += 1 }
            return child.sleep(for: 10)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertLessThanOrEqual(count.withLock { $0 }, 2)
    }
    func testScanBudgetAndInvalidConcurrencyCannotHang() {
        let start = Date()
        _ = NetworkScan.scan(maxConcurrent: 1, subnets: ["192.0.2"], budget: 0.05) { _, _, _, token in
            token.sleep(for: 10)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(NetworkScan.scan(maxConcurrent: 0, subnets: ["192.0.2"]), [])
    }
}
