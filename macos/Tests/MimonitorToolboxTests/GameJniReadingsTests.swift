import Foundation
import XCTest
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

/// Uses only existing APIs so the same failure fixtures can run against the parent revision.
@MainActor final class GameJniReadingsTests: XCTestCase {
    private final class Requests {
        private let lock = NSLock()
        private var storage: [CommandRequest] = []
        func append(_ request: CommandRequest) { lock.lock(); defer { lock.unlock() }; storage.append(request) }
        var all: [CommandRequest] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private let sourceKey = "mitv.tvplayer.hdmi.last.source"
    private let target = "192.0.2.17:5555"
    private let refresh = "am broadcast -a com.xiaomi.mitv.action.PIC_MODE_CHANGED --ei picmode 7"

    private func fixture(_ result: ProcessResult, source: String = "29") -> (PreviewRuntime, AppCoordinator, Requests) {
        let runtime = PreviewRuntime(), requests = Requests()
        runtime.display.values[sourceKey] = source
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources) { request in
            requests.append(request)
            if request.arguments.last?.contains("batchGet") == true { return result }
            return runtime.display.execute(request)
        }
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, presetDevice: base.presetDevice))
        state.adb.ip = "192.0.2.17"
        state.connectionStatus = .connected("fake")
        return (runtime, state, requests)
    }

    private func keys(_ source: String) -> (edid: String, freesync: String) {
        source == "29" || source == "30"
            ? ("g_fusion_picture__dp_edid_version", "g_video__dp_adaptive_sync")
            : ("g_fusion_picture__hdmi_edid_version", "g_video__freesync_switch")
    }

    private func batch(_ source: String, edid: String, freesync: String) -> String {
        let key = keys(source)
        return "\(key.edid)=\(edid)\n\(key.freesync)=\(freesync)\n"
    }

    private func batchCommand(_ keys: [String]) -> String {
        let file = "/sdcard/Download/Mimonitor_Toolbox/.mtk_batch_result.txt"
        let arguments = keys.map { "\\${IFS}\($0)" }.joined()
        return "mkdir -p /sdcard/Download/Mimonitor_Toolbox; rm -f \(file); service call TvService 3 s16 \"sh -c eval\\${IFS}CLASSPATH=/data/data/mitv.service/cache/MtkDirectTool.jar\\${IFS}/system/bin/app_process\\${IFS}/data/data/mitv.service/cache\\${IFS}MtkDirectTool\\${IFS}batchGet\(arguments)\" >/dev/null; i=0; while [ $i -lt 30 ] && [ ! -f \(file) ]; do sleep 0.1; i=$((i+1)); done; cat \(file) 2>/dev/null"
    }

    private func writeCommand(_ key: String, value: String) -> String {
        "service call TvService 3 s16 \"sh -c eval\\${IFS}CLASSPATH=/data/data/mitv.service/cache/MtkDirectTool.jar\\${IFS}/system/bin/app_process\\${IFS}/data/data/mitv.service/cache\\${IFS}MtkDirectTool\\${IFS}set\\${IFS}\(key)\\${IFS}\(value)\\${IFS}3\""
    }

    func testAllFourSourcesKeepIndependentValidOnAndOffEnums() {
        for source in ["29", "30", "23", "24"] {
            let dp = source == "29" || source == "30"
            for modeOn in [false, true] {
                for syncOn in [false, true] {
                    let output = batch(source, edid: modeOn ? (dp ? "3" : "6") : (dp ? "2" : "1"),
                                       freesync: syncOn ? (dp ? "1" : "3") : "0")
                    let (_, state, requests) = fixture(ProcessResult(output: output, exitCode: 0), source: source)
                    var values = [sourceKey: source]
                    state.applyGameJniMode(&values)
                    XCTAssertEqual(values["mode_320"], modeOn ? "1" : "0", source)
                    XCTAssertEqual(values["freesync"], syncOn ? "1" : "0", source)
                    XCTAssertEqual(requests.all.count, 1)
                    state.stop()
                }
            }
        }
    }

    func testEmptyAndErrorBatchNeverBecomeOffOrRetainOldValues() {
        for output in ["", "\n", "__error__=missing", "error: device offline", "g_fusion_picture__dp_edid_version=ERROR unavailable\ng_video__dp_adaptive_sync=ERROR unavailable"] {
            let (_, state, _) = fixture(ProcessResult(output: output, exitCode: 0))
            var values = [sourceKey: "29", "mode_320": "1", "freesync": "0"]
            state.applyGameJniMode(&values)
            XCTAssertEqual(values["mode_320"], "-1", output)
            XCTAssertEqual(values["freesync"], "-1", output)
            state.stop()
        }
    }

    func testIncompleteAndNonIntegerBatchConservativelyMakesBothUnknown() {
        for output in ["g_fusion_picture__dp_edid_version=3", "g_video__dp_adaptive_sync=1",
                       batch("29", edid: "", freesync: "1"), batch("29", edid: "3", freesync: "null"),
                       batch("29", edid: "N/A", freesync: "1"), batch("29", edid: "3", freesync: "1.5")] {
            let (_, state, _) = fixture(ProcessResult(output: output, exitCode: 0))
            var values = [sourceKey: "29"]
            state.applyGameJniMode(&values)
            XCTAssertEqual(values["mode_320"], "-1", output)
            XCTAssertEqual(values["freesync"], "-1", output)
            state.stop()
        }
    }

    func testUnknownIntegerEnumDoesNotDiscardOtherValidField() {
        for source in ["29", "23"] {
            let dp = source == "29"
            for invalid in ["-1", "99", String(Int.min), String(Int.max)] {
                for invalidMode in [false, true] {
                    let output = batch(source, edid: invalidMode ? invalid : (dp ? "3" : "6"),
                                       freesync: invalidMode ? (dp ? "1" : "3") : invalid)
                    let (_, state, _) = fixture(ProcessResult(output: output, exitCode: 0), source: source)
                    var values = [sourceKey: source]
                    state.applyGameJniMode(&values)
                    XCTAssertEqual(values["mode_320"], invalidMode ? "-1" : "1")
                    XCTAssertEqual(values["freesync"], invalidMode ? "1" : "-1")
                    state.stop()
                }
            }
        }
        for (source, mode, sync, expectedSync) in [("29", "6", "3", "-1"), ("23", "3", "1", "-1"),
                                                  ("29", "0", "0", "0"), ("23", "0", "0", "0")] {
            let (_, state, _) = fixture(ProcessResult(output: batch(source, edid: mode, freesync: sync), exitCode: 0), source: source)
            var values = [sourceKey: source]
            state.applyGameJniMode(&values)
            XCTAssertEqual(values["mode_320"], "-1")
            XCTAssertEqual(values["freesync"], expectedSync)
            state.stop()
        }
    }

    func testFailedProcessResultsRejectEvenApparentlyValidOutput() {
        let output = batch("29", edid: "3", freesync: "1")
        let results = [
            ProcessResult(output: output, exitCode: 1),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .timedOut),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .cancelled),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .signalled(15)),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .launchFailed(2)),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .ioFailure(5)),
            ProcessResult(standardOutput: output, exitCode: 0, outcome: .exited, outputTruncated: true),
            ProcessResult(standardOutput: output, standardError: "error: read failed", exitCode: 0, outcome: .exited)
        ]
        for result in results {
            let (_, state, requests) = fixture(result)
            var values = [sourceKey: "29", "mode_320": "0", "freesync": "1"]
            state.applyGameJniMode(&values)
            XCTAssertEqual(values["mode_320"], "-1", "\(result.outcome) / \(result.exitCode)")
            XCTAssertEqual(values["freesync"], "-1", "\(result.outcome) / \(result.exitCode)")
            XCTAssertEqual(requests.all.count, 1)
            state.stop()
        }
    }

    func testMissingOrUnknownSourceDoesNotGuessHDMIOrDispatchJNI() {
        for source in [nil, "", "null", "N/A", "-1", "0", "22", "31", " "] as [String?] {
            let (_, state, requests) = fixture(ProcessResult(output: batch("23", edid: "6", freesync: "3"), exitCode: 0))
            var values = ["mode_320": "1", "freesync": "0"]
            values[sourceKey] = source
            state.applyGameJniMode(&values)
            XCTAssertEqual(values["mode_320"], "-1")
            XCTAssertEqual(values["freesync"], "-1")
            XCTAssertTrue(requests.all.isEmpty, source ?? "missing")
            state.stop()
        }
    }

    func testSuccessfulReadKeepsOnePinnedBatchArgvAndTimeout() {
        for source in ["29", "30", "23", "24"] {
            let dp = source == "29" || source == "30", key = keys(source)
            let (_, state, requests) = fixture(ProcessResult(output: batch(source, edid: dp ? "2" : "1", freesync: "0"), exitCode: 0), source: source)
            var values = [sourceKey: source]
            state.applyGameJniMode(&values)
            XCTAssertEqual(requests.all.map(\.arguments), [["-s", target, "shell", batchCommand([key.edid, key.freesync])]])
            XCTAssertEqual(requests.all.map(\.timeout), [25])
            XCTAssertTrue(requests.all.allSatisfy { $0.executable == "/mock/adb" && $0.serverPort == "0" })
            state.stop()
        }
    }

    func testFailedRefreshReplacesPreviouslyKnownCacheAndMenuValue() async {
        for old in ["0", "1"] {
            let (_, state, requests) = fixture(ProcessResult(output: "", exitCode: 1))
            state.currentValues = ["mode_320": old, "freesync": old]
            state.refreshPage("game")
            await state.waitForPendingWork()
            XCTAssertEqual(state.currentValues["mode_320"], "-1")
            XCTAssertEqual(state.currentValues["freesync"], "-1")
            XCTAssertEqual(state.menuBarValue(for: "freesync"), -1)
            XCTAssertFalse(state.loadingPages.contains("game"))
            XCTAssertEqual(requests.all.count, 2)
            XCTAssertEqual(requests.all.first?.arguments, ["-s", target, "shell", "settings list global"])
            XCTAssertEqual(requests.all.last?.arguments, ["-s", target, "shell", batchCommand([keys("29").edid, keys("29").freesync])])
            state.stop()
        }
    }

    func testCancelledSessionProducesUnknownWithoutDispatch() {
        let (_, state, requests) = fixture(ProcessResult(output: batch("29", edid: "3", freesync: "1"), exitCode: 0))
        state.adb.session().cancellation.cancel()
        var values = [sourceKey: "29", "mode_320": "1", "freesync": "1"]
        state.applyGameJniMode(&values)
        XCTAssertEqual(values["mode_320"], "-1")
        XCTAssertEqual(values["freesync"], "-1")
        XCTAssertTrue(requests.all.isEmpty)
        state.stop()
    }

    func testMode320WritesKeepAllFourSourcesEnumsAndCommandOrder() async {
        for source in ["29", "30", "23", "24"] {
            for enabled in [false, true] {
                let dp = source == "29" || source == "30"
                let (_, state, requests) = fixture(ProcessResult(output: "", exitCode: 0), source: source)
                state.setMode320(enabled)
                await state.waitForPendingWork()
                let raw = enabled ? (dp ? "3" : "6") : (dp ? "2" : "1")
                XCTAssertEqual(requests.all.map(\.arguments), [
                    ["-s", target, "shell", "settings get global \(sourceKey)"],
                    ["-s", target, "shell", writeCommand(keys(source).edid, value: raw)],
                    ["-s", target, "shell", refresh]
                ])
                XCTAssertEqual(state.currentValues["mode_320"], enabled ? "1" : "0")
                state.stop()
            }
        }
    }

    func testFreeSyncWritesKeepAllFourSourcesEnumsAndCommandOrder() async {
        for source in ["29", "30", "23", "24"] {
            for enabled in [false, true] {
                let key = keys(source).freesync, dp = source == "29" || source == "30"
                let (_, state, requests) = fixture(ProcessResult(output: "\(key)=0", exitCode: 0), source: source)
                state.freesyncMemoryEnabled = false
                state.setFreesync(enabled)
                await state.waitForPendingWork()
                XCTAssertEqual(requests.all.map(\.arguments), [
                    ["-s", target, "shell", "settings get global \(sourceKey)"],
                    ["-s", target, "shell", batchCommand([key])],
                    ["-s", target, "shell", writeCommand(key, value: enabled ? (dp ? "1" : "3") : "0")],
                    ["-s", target, "shell", refresh]
                ])
                XCTAssertEqual(state.currentValues["freesync"], enabled ? "1" : "0")
                state.stop()
            }
        }
    }
}
