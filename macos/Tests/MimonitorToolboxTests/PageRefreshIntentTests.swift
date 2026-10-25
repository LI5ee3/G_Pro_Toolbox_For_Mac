import ToolboxDomain
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport
import ToolboxConcurrency
import Synchronization
import XCTest
@testable import MimonitorToolbox

final class PageRefreshIntentTests: XCTestCase {
    func testNewerRefreshInvalidatesOlderResultForTheSamePage() {
        var intent = PageRefreshIntent()
        let old = intent.begin("picture")
        let latest = intent.begin("picture")

        XCTAssertFalse(intent.isCurrent("picture", old))
        XCTAssertTrue(intent.isCurrent("picture", latest))
    }

    func testAnotherPagesRefreshDoesNotInvalidateThisPage() {
        var intent = PageRefreshIntent()
        let picture = intent.begin("picture")
        _ = intent.begin("game")

        XCTAssertTrue(intent.isCurrent("picture", picture))
    }
}

@MainActor
final class FailedPageRefreshTests: XCTestCase {
    func testFailedInitialReadsRemainReloadableAndDoNotLogSuccess() async {
        for failSettings in [true, false] {
            let runtime = PreviewRuntime(), failing = Mutex(true)
            let base = runtime.environment()
            let adb = AdbClient(resources: base.adb.resources) { request in
                let shell = request.arguments.last ?? ""
                if failing.withLock({ $0 }),
                   shell.contains(".mtk_batch_result.txt") || (failSettings &&
                    (shell == "settings list global" || shell.hasPrefix("for k in "))) {
                    return ProcessResult(output: "error: closed", exitCode: 1)
                }
                return runtime.display.execute(request)
            }
            let state = AppCoordinator(environment: AppEnvironment(mode: .simulation,
                preferences: base.preferences, adb: adb, hotkeys: base.hotkeys, feedback: base.feedback,
                scheduler: base.scheduler, system: base.system, now: base.now,
                presetDevice: base.presetDevice))
            runtime.display.configureDiscovery(rows: "000RefreshUSB device usb:fixture")
            state.connectUSB(serial: "000RefreshUSB"); await state.waitForPendingWork()
            state.refreshPage("picture"); await state.waitForPendingWork()
            XCTAssertFalse(state.loadedPages.contains("picture"))
            XCTAssertFalse(state.loadingPages.contains("picture"))
            XCTAssertFalse(state.logLines.contains { $0.contains("已刷新 picture") })
            XCTAssertTrue(state.logLines.contains { $0.contains("picture 页面读取不完整") })
            if failSettings { XCTAssertNil(state.currentValues["picture_backlight"]) }
            else { XCTAssertNotNil(state.currentValues["picture_mode"]) }
            // A later existing page request can recover; no timer/retry mechanism is added.
            failing.withLock { $0 = false }
            state.refreshPage("picture"); await state.waitForPendingWork()
            XCTAssertTrue(state.loadedPages.contains("picture"))
            XCTAssertNotNil(state.currentValues["picture_backlight"])
            XCTAssertTrue(state.logLines.contains { $0.contains("已刷新 picture") })
            state.stop()
        }
    }
}
