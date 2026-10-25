import XCTest
import Foundation
import ToolboxDomain
@testable import ToolboxMacAdapters
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class LogWriterTests: XCTestCase {
    private func temporary(_ test: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-log-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await test(directory)
    }
    func testConstructionDoesNotCreateDirectoryAndFIFOStopFlushesAllLines() async throws {
        try await temporary { root in
            let directory = root.appendingPathComponent("logs"), writer = LiveLogFile(directory: root.appendingPathComponent("logs"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
            writer.start("test")
            for i in 0..<1000 { writer.append("\(i)\n") }
            writer.stop(); await writer.drain()
            let result = try String(contentsOf: directory.appendingPathComponent("log_test.txt"), encoding: .utf8)
            XCTAssertEqual(result, (0..<1000).map { "\($0)\n" }.joined())
        }
    }
    func testRestartSameTimestampAppendsInsteadOfOverwriting() async throws {
        try await temporary { root in
            let writer = LiveLogFile(directory: root)
            writer.start("same"); writer.append("first\n"); writer.stop()
            writer.start("same"); writer.append("second\n"); writer.stop(); await writer.drain()
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("log_same.txt"), encoding: .utf8), "first\nsecond\n")
        }
    }
    func testActiveExportFlushesFullFileAndAtomicallyReplacesExistingDestination() async throws {
        try await temporary { root in
            let writer = LiveLogFile(directory: root)
            let target = root.appendingPathComponent("export.txt")
            try "old destination".write(to: target, atomically: true, encoding: .utf8)
            writer.start("full"); writer.append("full-history\n")
            let done = expectation(description: "export complete")
            writer.export(target, text: "only-ui-tail") { result in XCTAssertEqual(result, .success); done.fulfill() }
            await fulfillment(of: [done], timeout: 2)
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "full-history\n")
            writer.stop(); await writer.drain()
        }
    }
    func testStoppedExportUsesCurrentUISnapshotAndReportsWriteFailure() async throws {
        try await temporary { root in
            let writer = LiveLogFile(directory: root)
            writer.start("old"); writer.append("old\n"); writer.stop()
            let target = root.appendingPathComponent("export.txt"), done = expectation(description: "export snapshot")
            writer.export(target, text: "current UI") { result in XCTAssertEqual(result, .success); done.fulfill() }
            await fulfillment(of: [done], timeout: 2)
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "current UI")
            let failed = expectation(description: "export failure")
            writer.export(root.appendingPathComponent("missing/file.txt"), text: "text") { result in
                guard case .failure = result else { return XCTFail("false export success") }
                failed.fulfill()
            }
            await fulfillment(of: [failed], timeout: 2)
        }
    }
    func testWriteErrorIsReportedOnceAndOldObserverCannotReceiveOrPoisonNewSession() async throws {
        try await temporary { root in
            let notADirectory = root.appendingPathComponent("file")
            try Data().write(to: notADirectory)
            let writer = LiveLogFile(directory: notADirectory)
            var errors = 0
            let observation = writer.observeErrors { _ in errors += 1 }
            writer.start("test"); for _ in 0..<100 { writer.append("ignored") }
            await writer.drain(); XCTAssertEqual(errors, 1)
            observation.invalidate()
            writer.start("old")
            let next = writer.observeErrors { _ in XCTFail("old operation reported into new subscriber") }
            await writer.drain(); next.invalidate()
        }
    }
    func testExportingIntoCurrentLiveFileDoesNotBreakFutureWrites() async throws {
        try await temporary { root in
            let writer = LiveLogFile(directory: root), target = root.appendingPathComponent("log_same.txt")
            writer.start("same"); writer.append("a")
            let done = expectation(description: "same path export")
            writer.export(target, text: "wrong") { result in XCTAssertEqual(result, .success); done.fulfill() }
            await fulfillment(of: [done], timeout: 2)
            writer.append("b"); writer.stop(); await writer.drain()
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "ab")
        }
    }
    func testCoordinatorReportsExportFailureInsteadOfSuccess() async {
        let runtime = PreviewRuntime(), base = runtime.environment()
        var system = base.system
        system.exportLog = { _, _, completion in completion(.failure("denied")) }
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: base.adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: system, now: base.now, presetDevice: base.presetDevice))
        state.exportLog(to: URL(fileURLWithPath: "/mock/export.txt")); await state.waitForPendingWork()
        XCTAssertTrue(state.logLines.contains { $0.contains("导出失败") })
        XCTAssertFalse(state.logLines.contains { $0.contains("已导出") })
    }
}
