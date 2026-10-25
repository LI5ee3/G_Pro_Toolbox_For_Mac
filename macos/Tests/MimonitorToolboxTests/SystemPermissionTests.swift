import XCTest
import Foundation
import AppKit
import ToolboxDomain
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class SystemPermissionTests: XCTestCase {
    private func state(_ runtime: PreviewRuntime, system: SystemActions, hotkeys: HotkeyManager? = nil, mode: AppEnvironment.Mode = .live) -> AppCoordinator {
        let base = runtime.environment(mode: mode)
        return AppCoordinator(environment: AppEnvironment(mode: mode, preferences: base.preferences, adb: base.adb,
            hotkeys: hotkeys ?? base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: system, now: base.now, presetDevice: base.presetDevice))
    }
    func testDeniedGrantRevokeAndRegrantOwnListenerWithoutAutomaticPrompt() async {
        let runtime = PreviewRuntime()
        runtime.preferences.set(true, forKey: "media_volume_keys_enabled")
        var trusted = false, prompts = 0
        var actions = runtime.environment().system
        actions.isTrusted = { trusted }; actions.promptAccessibility = { prompts += 1; return trusted }
        let state = state(runtime, system: actions)
        state.start()
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
        XCTAssertEqual(state.keyboard.listenerStatus, .permissionRequired)
        trusted = true; state.refreshAccessibilityStatus()
        XCTAssertEqual(runtime.hotkeyDriver.starts, 1); XCTAssertEqual(state.keyboard.listenerStatus, .running)
        state.refreshAccessibilityStatus(); XCTAssertEqual(runtime.hotkeyDriver.starts, 1)
        let stops = runtime.hotkeyDriver.stops
        trusted = false; state.refreshAccessibilityStatus()
        XCTAssertGreaterThan(runtime.hotkeyDriver.stops, stops)
        XCTAssertEqual(state.keyboard.listenerStatus, .permissionRequired)
        trusted = true; state.refreshAccessibilityStatus()
        XCTAssertEqual(runtime.hotkeyDriver.starts, 2)
        XCTAssertEqual(prompts, 0)
        state.stop(); await state.waitForPendingWork()
    }
    func testNoConfiguredControlsDoesNotTapKeyboardAndOnlyExplicitActionPrompts() async {
        let runtime = PreviewRuntime()
        var actions = runtime.environment().system
        var prompts = 0
        actions.isTrusted = { false }; actions.promptAccessibility = { prompts += 1; return false }
        let state = state(runtime, system: actions)
        state.start()
        XCTAssertEqual(state.keyboard.listenerStatus, .stopped)
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0); XCTAssertEqual(prompts, 0)
        state.requestAccessibilityPermission(); XCTAssertEqual(prompts, 1)
        state.openAutomationSettings(); state.openLocalNetworkSettings()
        XCTAssertTrue(runtime.effects.contains("automation.settings")); XCTAssertTrue(runtime.effects.contains("network.settings"))
        state.stop(); await state.waitForPendingWork()
    }
    func testApplicationActivationRefreshesPermissionAndUnsubscribesOnStop() async {
        let runtime = PreviewRuntime()
        var trusted = false
        var activate: (() -> Void)?
        var actions = runtime.environment().system
        actions.isTrusted = { trusted }
        actions.observeActivation = { action in activate = action; return RuntimeCancellation { activate = nil } }
        let state = state(runtime, system: actions)
        state.mediaVolumeKeysEnabled = true; state.start()
        trusted = true; activate?()
        XCTAssertEqual(state.keyboard.listenerStatus, .running)
        state.stop(); XCTAssertNil(activate)
        await state.waitForPendingWork()
    }
    func testNetworkSettingsFailureGivesManualPathWithoutClaimingSuccessOrGrant() async {
        let runtime = PreviewRuntime()
        var actions = runtime.environment().system
        var opened = 0
        actions.openLocalNetwork = { opened += 1; return false }
        let state = state(runtime, system: actions, mode: .simulation)
        state.openLocalNetworkSettings()
        await state.waitForPendingWork()
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(state.logLines.contains { $0.contains("无法打开系统设置") && $0.contains("隐私与安全 → 本地网络") })
        XCTAssertFalse(state.logLines.contains { $0.contains("已请求打开") })
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
        XCTAssertTrue(runtime.effects.isEmpty)
    }
    func testPreviewNetworkSettingsOnlyRecordsIntentAndExplainsRemainingStep() async {
        let runtime = PreviewRuntime(), state = runtime.makeState(.permissionDenied)
        state.openLocalNetworkSettings()
        await state.waitForPendingWork()
        XCTAssertEqual(runtime.effects, ["network.settings"])
        XCTAssertTrue(state.logLines.contains { $0.contains("请选择“本地网络”") })
        XCTAssertFalse(state.keyboard.accessibilityTrusted)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
        XCTAssertEqual(runtime.scheduler.pendingCount, 0)
    }
    func testTapFailureIsDistinctFromAccessibilityDenialAndCanRetry() async {
        final class Driver: HotkeyDriving {
            var succeeds = false
            func start(handler: @escaping (CGEventType, CGEvent) -> Bool, onDisabled: @escaping () -> Void) -> Bool { succeeds }
            func stop() {}
        }
        let runtime = PreviewRuntime(), driver = Driver()
        var actions = runtime.environment().system; actions.isTrusted = { true }
        let state = state(runtime, system: actions, hotkeys: HotkeyManager(driver: driver))
        state.mediaVolumeKeysEnabled = true; state.start()
        XCTAssertTrue(state.keyboard.accessibilityTrusted); XCTAssertEqual(state.keyboard.listenerStatus, .failed)
        driver.succeeds = true; state.refreshAccessibilityStatus()
        XCTAssertEqual(state.keyboard.listenerStatus, .running)
        state.stop(); await state.waitForPendingWork()
    }
    func testTerminalDeniedAndFailureAreNotLoggedAsSuccessfulLaunch() async {
        let runtime = PreviewRuntime()
        var actions = runtime.environment().system
        actions.terminal = { _, _ in TerminalResult(outcome: .denied, detail: "-1743") }
        let state = state(runtime, system: actions, mode: .simulation)
        state.openAdbCmd(); XCTAssertTrue(state.settings.terminalBusy)
        await state.waitForPendingWork()
        XCTAssertEqual(state.settings.terminalResult?.outcome, .denied)
        XCTAssertFalse(state.settings.terminalBusy)
        XCTAssertFalse(state.logLines.contains { $0.contains("已在终端打开") })
        XCTAssertTrue(state.logLines.contains { $0.contains("授权被拒绝") })
    }
    func testTerminalCapturesTargetAndEscapesPathAndPortAsShellData() async {
        let runtime = PreviewRuntime()
        var scripts: [String] = []
        var actions = runtime.environment().system
        actions.terminal = { script, _ in scripts.append(script); return TerminalResult(outcome: .opened) }
        let state = state(runtime, system: actions, mode: .simulation)
        state.adb.ip = "192.0.2.1"; state.connectionStatus = .connected("fake")
        state.openAdbShell(); state.adb.beginSession(ip: "192.0.2.2")
        await state.waitForPendingWork()
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("adb -s '192.0.2.1:5555' shell"))
        XCTAssertTrue(scripts[0].contains("Mimonitor · Shell · 192.0.2.1:5555"))
        XCTAssertFalse(scripts[0].contains("192.0.2.2"))
        XCTAssertTrue(scripts[0].contains("export ANDROID_ADB_SERVER_PORT='0'"))
    }
}

final class TerminalExecutionTests: XCTestCase {
    func testOnlyCompletedSuccessfulProcessConfirmsTerminal() {
        XCTAssertEqual(TerminalExecution.result(ProcessResult(output: "", exitCode: 0)).outcome, .opened)
        XCTAssertEqual(TerminalExecution.result(ProcessResult(output: "not authorized (-1743)", exitCode: 1)).outcome, .denied)
        XCTAssertEqual(TerminalExecution.result(ProcessResult(output: "script error", exitCode: 1)).outcome, .failed)
        XCTAssertEqual(TerminalExecution.result(ProcessResult(standardOutput: "success", exitCode: -1, outcome: .timedOut)).outcome, .failed)
        XCTAssertEqual(TerminalExecution.result(.cancelled).outcome, .failed)
        XCTAssertEqual(TerminalExecution.result(ProcessResult(standardOutput: "", exitCode: 0, outcome: .exited, outputTruncated: true)).outcome, .failed)
    }
    func testShellQuotingKeepsMetacharactersAndSingleQuotesLiteral() {
        XCTAssertEqual(TerminalExecution.shellQuote("/tmp/a b/$(x)`y`"), "'/tmp/a b/$(x)`y`'")
        XCTAssertEqual(TerminalExecution.shellQuote("a'b"), "'a'\\''b'")
        XCTAssertEqual(TerminalExecution.shellQuote(""), "''")
    }
}
