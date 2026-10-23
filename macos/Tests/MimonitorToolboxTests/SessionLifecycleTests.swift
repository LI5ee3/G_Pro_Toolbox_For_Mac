import Foundation
import XCTest
import Synchronization
import ToolboxConcurrency
import ToolboxDomain
import ToolboxMacAdapters
import MimonitorPresetCore
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor
final class SessionLifecycleTests: XCTestCase {
    private let usb = "000LifecycleUSB"

    private func fixture(_ runtime: PreviewRuntime, live: Bool = false,
                         system: SystemActions? = nil,
                         intercept: @escaping (CommandRequest) -> ProcessResult? = { _ in nil }) -> AppCoordinator {
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources) { request in
            intercept(request) ?? runtime.display.execute(request)
        }
        return AppCoordinator(environment: AppEnvironment(mode: live ? .live : .simulation,
            preferences: base.preferences, adb: adb, hotkeys: base.hotkeys, feedback: base.feedback,
            scheduler: base.scheduler, system: system ?? base.system, now: base.now, calendar: base.calendar,
            presetDevice: { AdbPresetDevice(adb: $0, endpoint: $1, identity: $2) }))
    }

    private func confirm(_ state: AppCoordinator) async throws {
        state.confirmConnectionOwnership(includeMemories: false,
            expectedSessionID: try XCTUnwrap(state.connection.identitySessionID),
            expectedProfileToken: state.connection.ownershipConfirmationToken)
        await state.waitForPendingWork()
    }

    func testUSBHealthLossAndReappearanceUseFreshEnumerationWithoutTCPFallback() async throws {
        let runtime = PreviewRuntime(), offline = Mutex(false)
        let enumeratedAfterLoss = expectation(description: "USB freshly enumerated after loss")
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        runtime.display.configureDiscovery(rows: "\(usb) device usb:fixture")
        let state = fixture(runtime, intercept: { request in
            if request.arguments == ["devices", "-l"], offline.withLock({ $0 }) {
                enumeratedAfterLoss.fulfill()
            }
            if request.arguments.last == "get-state", offline.withLock({ $0 }) {
                return ProcessResult(output: "offline", exitCode: 1)
            }
            return nil
        })
        state.connectUSB(serial: usb); await state.waitForPendingWork(); try await confirm(state)
        let session = state.adb.session(), evidence = state.connection.identityEvidence
        state.currentValues = ["picture_contrast": "71"]; state.loadedPages = ["picture"]
        let beforeHealth = runtime.display.recordedCommands.count
        state.monitorAdbServer(); await state.waitForPendingWork()
        XCTAssertEqual(Array(runtime.display.recordedCommands.dropFirst(beforeHealth)), [
            "-s \(usb) get-state", "-s \(usb) shell echo __mimonitor_probe__"])
        XCTAssertEqual(state.adb.session().sessionID, session.sessionID)
        XCTAssertEqual(state.connection.identityEvidence, evidence)
        XCTAssertEqual(state.currentValues, ["picture_contrast": "71"])
        XCTAssertEqual(state.loadedPages, ["picture"])

        state.deviceQueue.suspend()
        state.key("KEYCODE_DPAD_CENTER")
        offline.withLock { $0 = true }; runtime.display.configureDiscovery(rows: "")
        state.monitorAdbServer()
        await fulfillment(of: [enumeratedAfterLoss], timeout: 3)
        state.deviceQueue.resume(); await state.waitForPendingWork()
        XCTAssertTrue(session.cancellation.isCancelled)
        XCTAssertFalse(state.isConnected); XCTAssertTrue(state.currentValues.isEmpty)
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("KEYCODE_DPAD_CENTER") })

        let beforeRecovery = runtime.display.recordedCommands.count
        offline.withLock { $0 = false }
        runtime.display.configureDiscovery(rows: "\(usb) device usb:fixture")
        state.monitorAdbServer(); await state.waitForPendingWork()
        let recovered = Array(runtime.display.recordedCommands.dropFirst(beforeRecovery))
        XCTAssertEqual(Array(recovered.prefix(5)), ["devices -l", "-s \(usb) get-state",
            "-s \(usb) shell echo __mimonitor_probe__", "-s \(usb) shell getprop ro.serialno",
            "-s \(usb) shell getprop ro.boot.serialno"])
        XCTAssertTrue(state.isConnected); XCTAssertTrue(state.connection.allowsIdentityAutomaticActions)
        XCTAssertNotEqual(state.adb.session().sessionID, session.sessionID)
        XCTAssertTrue(recovered.contains { $0.contains("settings list global") })
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("192.0.2.99") || $0.hasPrefix("connect ") })
        state.disconnectAdb(); await state.waitForPendingWork()
        let disconnected = runtime.display.recordedCommands.count
        state.monitorAdbServer(); state.recoverAfterWake(); runtime.scheduler.advance(by: 60)
        await state.waitForPendingWork()
        XCTAssertEqual(runtime.display.recordedCommands.count, disconnected)
        XCTAssertFalse(state.isConnected)
        state.stop()
    }

    func testDuplicateWakeAndStopStartRevalidateOnceAndKeepManualSuppression() async throws {
        let runtime = PreviewRuntime()
        var system = runtime.environment().system
        var wake: (() -> Void)?, screenWake: (() -> Void)?
        var observers = 0
        system.observeWake = { first, second in
            wake = first; screenWake = second; observers += 1
            return RuntimeCancellation { observers -= 1 }
        }
        let state = fixture(runtime, live: true, system: system)
        state.start(); state.ipInput = "192.0.2.27"; state.connect()
        await state.waitForPendingWork(); try await confirm(state)
        // Complete each wake before the next notification, proving this is not queue timing luck.
        wake?(); runtime.scheduler.advance(by: 1.5); await state.waitForPendingWork()
        let settled = state.adb.session(), beforeSecond = runtime.display.recordedCommands.count
        screenWake?(); runtime.scheduler.advance(by: 1.5); await state.waitForPendingWork()
        XCTAssertEqual(state.adb.session().sessionID, settled.sessionID)
        XCTAssertFalse(runtime.display.recordedCommands.dropFirst(beforeSecond).contains { $0.contains("getprop ro.serialno") })
        state.stop()
        XCTAssertFalse(state.isConnected); XCTAssertTrue(settled.cancellation.isCancelled)
        XCTAssertEqual(observers, 0)
        state.start(); state.start(); XCTAssertEqual(observers, 1)
        runtime.scheduler.advance(by: 1.5); await state.waitForPendingWork()
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.connection.identityEvidence?.sessionID, state.adb.session().sessionID)
        state.disconnectAdb(); await state.waitForPendingWork(); state.stop(); state.start()
        let beforeSuppressed = runtime.display.recordedCommands.filter { $0 != "start-server" }.count
        wake?(); screenWake?(); runtime.scheduler.advance(by: 30); await state.waitForPendingWork()
        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0 != "start-server" }.count, beforeSuppressed)
        state.stop(); XCTAssertEqual(observers, 0)
    }

    func testSleepCancelsInFlightQueuedAndDelayedWorkBeforeWakeReadmission() async throws {
        let runtime = PreviewRuntime(), armed = Mutex(false)
        let began = expectation(description: "old write running")
        var sleep: (() -> Void)?, wake: (() -> Void)?, screenWake: (() -> Void)?
        var observers = 0, cancelled = false
        var system = runtime.environment().system
        system.observeSleep = { callback in
            sleep = callback; observers += 1
            return RuntimeCancellation { observers -= 1 }
        }
        system.observeWake = { first, second in
            wake = first; screenWake = second; observers += 1
            return RuntimeCancellation { observers -= 1 }
        }
        let state = fixture(runtime, live: true, system: system, intercept: { request in
            if request.arguments.last == "input keyevent KEYCODE_DPAD_CENTER", armed.withLock({ $0 }) {
                began.fulfill()
                _ = request.cancellation.sleep(for: 3)
                return ProcessResult(output: "late success", exitCode: 0)
            }
            return nil
        })
        state.start(); state.ipInput = "192.0.2.27"; state.connect()
        await state.waitForPendingWork(); try await confirm(state)
        let old = state.adb.session(), before = runtime.display.recordedCommands.count
        armed.withLock { $0 = true }
        state.runBackground(onCancel: { cancelled = true }) {
            state.adb.keyevent("KEYCODE_DPAD_CENTER")
            state.publish { state.dashboardVolume = 99 }
        }
        await fulfillment(of: [began], timeout: 3)
        state.key("KEYCODE_DPAD_UP")
        state.mediaBrightnessPreview = 78; state.mediaBrightnessHardware = 45
        state.scheduleMediaBrightnessTrailing()
        sleep?(); sleep?()
        XCTAssertTrue(old.cancellation.isCancelled); XCTAssertFalse(state.isConnected)
        state.start() // A duplicate start cannot resume the sleeping session.
        XCTAssertTrue(state.adb.session().cancellation.isCancelled)
        runtime.scheduler.advance(by: 20); await state.waitForPendingWork()
        XCTAssertTrue(cancelled); XCTAssertFalse(state.mediaBrightnessCommitInFlight)
        XCTAssertNil(state.dashboardVolume)
        XCTAssertEqual(runtime.display.recordedCommands.count, before)
        wake?(); screenWake?(); runtime.scheduler.advance(by: 1.5); await state.waitForPendingWork()
        let recovery = Array(runtime.display.recordedCommands.dropFirst(before))
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(recovery.filter { $0.contains("getprop ro.serialno") }.count, 1)
        XCTAssertTrue(recovery.contains { $0.contains("settings list global") })
        XCTAssertFalse(recovery.contains { $0.contains("KEYCODE_DPAD_UP") || $0.contains("settings put") })
        XCTAssertNotEqual(state.dashboardVolume, 99)
        state.disconnectAdb(); await state.waitForPendingWork()
        sleep?(); wake?(); screenWake?()
        let offline = runtime.display.recordedCommands.count
        state.refreshDevices(); await state.waitForPendingWork()
        XCTAssertEqual(Array(runtime.display.recordedCommands.dropFirst(offline)), ["devices -l"])
        XCTAssertFalse(state.isConnected); XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
        state.stop(); XCTAssertEqual(observers, 0)
    }

    func testSameEndpointRecoveryRevalidatesBinderCapability() throws {
        let runtime = PreviewRuntime(), state = fixture(runtime)
        state.adb.beginSession(ip: "192.0.2.27")
        XCTAssertEqual(try state.adb.setMediaVolume(27), .binder)
        XCTAssertEqual(try state.adb.setMediaVolume(28), .binder)
        let before = runtime.display.recordedCommands.count
        state.adb.beginSession(ip: "192.0.2.27")
        XCTAssertEqual(try state.adb.setMediaVolume(29), .binder)
        XCTAssertEqual(runtime.display.recordedCommands.dropFirst(before).filter { $0.contains("service call audio 22") }.count, 1)
        state.stop()
    }

    func testPartiallyDispatchedAutomaticPresetIsNotReplayedAfterReconnect() async throws {
        for restart in [false, true] {
            let runtime = PreviewRuntime(), armed = Mutex(false)
            let began = expectation(description: "preset first write dispatched"), release = DispatchSemaphore(value: 0)
            let state = fixture(runtime, live: restart, intercept: { request in
                if request.arguments.last == "settings put global picture_mode 14",
                   armed.withLock({ value in if !value { return false }; value = false; return true }) {
                    // Apply this first write, then return it late after the session has been cancelled.
                    let result = runtime.display.execute(request)
                    began.fulfill(); _ = release.wait(timeout: .now() + 3)
                    return result
                }
                return nil
            })
            if restart { state.start() }
            state.ipInput = "192.0.2.27"; state.connect(); await state.waitForPendingWork(); try await confirm(state)
            state.createPreset(name: "original"); await state.waitForPendingWork()
            let baseline = state.presetConfiguration.baseline
            state.connection.allowsIdentityAutomaticActions = false
            let minute = state.currentMinute()
            func time(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
            state.saveAutomaticTask(ScheduledPresetTask(id: "lifecycle", presetID: PicturePreset.baselineID,
                start: time(minute), end: time((minute + 10) % 1440)))
            await state.waitForPendingWork()
            state.connection.allowsIdentityAutomaticActions = true; armed.withLock { $0 = true }
            state.checkAutomaticTasks(); await fulfillment(of: [began], timeout: 3)
            let before = runtime.display.recordedCommands.count
            if restart {
                // Restart and reconnect before the old completion returns. The startup snapshot is
                // cancelled by connect, so admission must reload the worker's completed accounting.
                state.stop(); state.start(); state.connect(); release.signal()
            } else {
                state.disconnectAdb(); release.signal(); await state.waitForPendingWork()
                XCTAssertTrue(state.presetConfiguration.applicationIncomplete)
                XCTAssertFalse(state.isPresetOperationInFlight); XCTAssertFalse(state.isPresetBusy)
                state.connect()
            }
            await state.waitForPendingWork()
            state.checkAutomaticTasks(); await state.waitForPendingWork()
            XCTAssertFalse(runtime.display.recordedCommands.dropFirst(before).contains { $0.contains("settings put") })
            XCTAssertTrue(state.presetConfiguration.applicationIncomplete)
            XCTAssertEqual(state.presetConfiguration.session?.taskID, "lifecycle")
            XCTAssertNil(state.presetConfiguration.session?.appliedTargetID)
            XCTAssertEqual(state.presetConfiguration.baseline, baseline)
            XCTAssertFalse(state.isPresetOperationInFlight); XCTAssertFalse(state.isPresetBusy)
            state.stop()
        }
    }
}
