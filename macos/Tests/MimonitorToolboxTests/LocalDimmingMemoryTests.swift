import Foundation
import XCTest
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class LocalDimmingMemoryTests: XCTestCase {
    private func fixture(_ data: Data) -> (PreviewRuntime, AppCoordinator) {
        let runtime = PreviewRuntime()
        runtime.preferences.set(data, forKey: "local_dimming_memory")
        let state = AppCoordinator(environment: runtime.environment())
        state.adb.ip = "192.0.2.16"
        state.connectionStatus = .connected("fake")
        return (runtime, state)
    }

    func testInvalidMemoryStatusDoesNotCrashOrRewriteOriginalBytes() throws {
        for value in [-1, 4, Int.min, Int.max] {
            let data = try JSONEncoder().encode(["sdr": value, "hdr": value])
            let (runtime, state) = fixture(data)
            state.updateHdrMemoryStatus()
            XCTAssertTrue(state.hdrMemoryStatusText.contains("SDR=-- / HDR=--"))
            XCTAssertEqual(state.localDimmingMemory(), ["sdr": value, "hdr": value])
            XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
            XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
            state.stop()
        }
    }

    func testMalformedMemoryIsIgnoredWithoutRewritingOrCommands() async {
        for json in ["{ damaged", "[]", "null", "{\"sdr\":\"3\"}", "{\"hdr\":1.5}", "{\"hdr\":9223372036854775808}"] {
            let data = Data(json.utf8), (runtime, state) = fixture(Data(json.utf8))
            state.updateHdrMemoryStatus()
            state.applyHdrMemory(state: false); state.applyHdrMemory(state: true)
            await state.waitForPendingWork()
            XCTAssertTrue(state.localDimmingMemory().isEmpty)
            XCTAssertTrue(state.hdrMemoryStatusText.contains("SDR=-- / HDR=--"))
            XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
            XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
            state.stop()
        }
    }

    func testInvalidRememberedValueNeverReadsOrWritesDevice() async throws {
        for value in [-1, 4, Int.min, Int.max] {
            let data = try JSONEncoder().encode(["sdr": value, "hdr": value])
            let (runtime, state) = fixture(data)
            state.applyHdrMemory(state: false); state.applyHdrMemory(state: true)
            await state.waitForPendingWork()
            XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
            XCTAssertTrue(runtime.feedback.hints.isEmpty)
            XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
            state.stop()
        }
    }

    func testInvalidDirectValueDoesNotChangeReadingsPreferencesOrDispatch() async {
        let data = Data("{ \"sdr\": 2, \"hdr\": 3 }".utf8), (runtime, state) = fixture(Data("{ \"sdr\": 2, \"hdr\": 3 }".utf8))
        state.currentValues = ["picture_local_dimming": "2"]
        state.hdrMemoryEnabled = true; state.hdrLastState = false
        for value in [-1, 4, Int.min, Int.max] { state.setLocalDimming(value) }
        await state.waitForPendingWork()
        XCTAssertEqual(state.currentValues["picture_local_dimming"], "2")
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
        state.stop()
    }

    func testValidMemoryStatusKeepsFourExistingLabelsAndOriginalBytes() {
        for (value, name) in ["关", "低", "中", "高"].enumerated() {
            let data = Data("{ \"sdr\": \(value), \"hdr\": \(value) }".utf8), (runtime, state) = fixture(Data("{ \"sdr\": \(value), \"hdr\": \(value) }".utf8))
            state.updateHdrMemoryStatus()
            XCTAssertTrue(state.hdrMemoryStatusText.contains("SDR=\(name) / HDR=\(name)"))
            XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
            state.stop()
        }
    }

    func testValidRestoreKeepsPinnedCommandOrderAndValues() async throws {
        for value in 0...3 {
            for hdr in [false, true] {
                let data = try JSONEncoder().encode([hdr ? "hdr" : "sdr": value])
                let (runtime, state) = fixture(data)
                runtime.display.values["picture_local_dimming"] = String((value + 1) % 4)
                state.applyHdrMemory(state: hdr)
                await state.waitForPendingWork()
                XCTAssertEqual(runtime.display.recordedCommands, [
                    "-s 192.0.2.16:5555 shell settings get global picture_local_dimming",
                    "-s 192.0.2.16:5555 shell service call TvService 3 s16 \"sh -c eval\\${IFS}CLASSPATH=/data/data/mitv.service/cache/MtkDirectTool.jar\\${IFS}/system/bin/app_process\\${IFS}/data/data/mitv.service/cache\\${IFS}MtkDirectTool\\${IFS}set\\${IFS}g_video__vid_local_dimming\\${IFS}\(value)\\${IFS}3\"",
                    "-s 192.0.2.16:5555 shell settings put global picture_local_dimming \(value)",
                    "-s 192.0.2.16:5555 shell settings put global tv_picture_video_local_dimming \(value)",
                    "-s 192.0.2.16:5555 shell am broadcast -a com.xiaomi.mitv.action.PIC_MODE_CHANGED --ei picmode 7"
                ])
                XCTAssertEqual(state.currentValues["picture_local_dimming"], String(value))
                XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), data)
                state.stop()
            }
        }
    }

    func testValidAlreadyAppliedMemoryDoesNotWriteAgain() async {
        let (runtime, state) = fixture(Data("{\"sdr\":3}".utf8))
        runtime.display.values["picture_local_dimming"] = "3"
        state.applyHdrMemory(state: false)
        await state.waitForPendingWork()
        XCTAssertEqual(runtime.display.recordedCommands, ["-s 192.0.2.16:5555 shell settings get global picture_local_dimming"])
        state.stop()
    }

    func testExplicitValidWritePreservesUnrelatedInvalidMemoryEntries() async {
        let (runtime, state) = fixture(Data("{\"sdr\":2,\"hdr\":-1,\"future\":99}".utf8))
        state.hdrMemoryEnabled = true; state.hdrLastState = false
        state.setLocalDimming(1)
        await state.waitForPendingWork()
        XCTAssertEqual(state.localDimmingMemory(), ["sdr": 1, "hdr": -1, "future": 99])
        XCTAssertTrue(state.hdrMemoryStatusText.contains("SDR=低 / HDR=--"))
        XCTAssertEqual(runtime.display.recordedCommands.count, 4)
        state.stop()
    }
}
