import Foundation
import XCTest
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

final class MediaControlResultTests: XCTestCase {
    private let success = ProcessResult(output: "Result: Parcel(00000000)", exitCode: 0)
    private let failure = ProcessResult(output: "error: simulated failure", exitCode: 1)

    private func client(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AdbClient {
        let adb = AdbClient(resources: RuntimeResources(adbPath: "/fake/adb", serverPort: "0",
            runtime: { _ in nil }, guardianAPK: { nil }), execute: execute)
        adb.ip = "192.0.2.1"
        return adb
    }

    func testVerifiedBinderKeepsFastPathWithoutPerWriteReadback() throws {
        var commands: [String] = []
        let adb = client { request in
            let command = request.arguments.last!
            commands.append(command)
            if command.contains("audio 22") { return ProcessResult(output: "Result: Parcel(00000000 0000001b)", exitCode: 0) }
            return self.success
        }
        XCTAssertEqual(try adb.setMediaVolume(27), .binder)
        XCTAssertEqual(try adb.setMediaVolume(28), .binder)
        XCTAssertEqual(try adb.setMediaMuted(true), .binder)
        XCTAssertEqual(commands.count, 4)
        XCTAssertEqual(commands.filter { $0.contains("audio 22") }.count, 1)
        XCTAssertFalse(commands.contains { $0.contains("audio 17") || $0.contains("keyevent") })
    }

    func testFailedProcessCannotProveBinderSuccessButSuccessfulFallbackCan() throws {
        for result in [ProcessResult(output: "Result: Parcel(00000000)", exitCode: 1),
                       ProcessResult(standardOutput: "Result: Parcel(00000000)", exitCode: -1, outcome: .timedOut),
                       ProcessResult(standardOutput: "Result: Parcel(00000000)", exitCode: 0, outcome: .exited, outputTruncated: true)] {
            var commands: [String] = []
            let adb = client { request in
                let command = request.arguments.last!
                commands.append(command)
                if command.contains("audio 12") { return result }
                if command.contains("audio 22") { return ProcessResult(output: "Result: Parcel(00000000 0000000a)", exitCode: 0) }
                return ProcessResult(output: "", exitCode: 0)
            }
            XCTAssertEqual(try adb.setMediaVolume(12), .keyevent)
            XCTAssertEqual(commands.last, "input keyevent KEYCODE_VOLUME_UP KEYCODE_VOLUME_UP")
        }
    }

    func testVolumeFallbackRequiresSuccessfulReadAndSuccessfulKeyevent() {
        for canRead in [false, true] {
            var commands: [String] = []
            let adb = client { request in
                let command = request.arguments.last!
                commands.append(command)
                if command.contains("audio 22") {
                    return ProcessResult(output: "Result: Parcel(00000000 0000000a)", exitCode: canRead ? 0 : 1)
                }
                if command == "settings get system volume_music_speaker" { return ProcessResult(output: "10", exitCode: 1) }
                return self.failure
            }
            XCTAssertThrowsError(try adb.setMediaVolume(12))
            XCTAssertEqual(commands.filter { $0.contains("keyevent") }.count, canRead ? 1 : 0)
        }
    }

    func testMuteWriteWithUnreadableResultDoesNotToggleAgain() {
        for target in [true, false] {
            var commands: [String] = []
            let adb = client { request in
                let command = request.arguments.last!
                commands.append(command)
                return command.contains("audio 10") ? self.success : self.failure
            }
            XCTAssertThrowsError(try adb.setMediaMuted(target)) { error in
                XCTAssertTrue(error.localizedDescription.contains("无法读回确认"))
            }
            XCTAssertEqual(commands.count, 2)
            XCTAssertFalse(commands.contains { $0.contains("keyevent") })
        }
    }

    func testMuteFallbackOnlyTogglesKnownDifferentStateAndChecksExecution() throws {
        for target in [true, false] {
            for current in [nil, Optional(target), Optional(!target)] {
                for keyeventSucceeds in [false, true] {
                    var commands: [String] = []
                    let adb = client { request in
                        let command = request.arguments.last!
                        commands.append(command)
                        if command.contains("audio 17"), let current {
                            return ProcessResult(output: "Result: Parcel(00000000 \(current ? "00000001" : "00000000"))", exitCode: 0)
                        }
                        if command.contains("keyevent"), keyeventSucceeds { return ProcessResult(output: "", exitCode: 0) }
                        return self.failure
                    }
                    if current == target {
                        XCTAssertEqual(try adb.setMediaMuted(target), .alreadyAtTarget)
                    } else if current != nil && keyeventSucceeds {
                        XCTAssertEqual(try adb.setMediaMuted(target), .keyevent)
                    } else {
                        XCTAssertThrowsError(try adb.setMediaMuted(target))
                    }
                    XCTAssertEqual(commands.filter { $0.contains("keyevent") }.count,
                                   current != nil && current != target ? 1 : 0)
                }
            }
        }
    }

    func testUnmuteFailureOrUnconfirmedResultStopsVolumeWrite() {
        for binderAccepted in [false, true] {
            var commands: [String] = []
            let adb = client { request in
                let command = request.arguments.last!
                commands.append(command)
                return binderAccepted && command.contains("audio 10") ? self.success : self.failure
            }
            XCTAssertThrowsError(try adb.setMediaVolume(27, unmuteFirst: true)) { error in
                XCTAssertTrue(error.localizedDescription.contains("解除静音失败，未设置音量"))
            }
            XCTAssertFalse(commands.contains { $0.contains("audio 12") || $0.contains("keyevent") })
        }
    }
}

@MainActor
final class MediaControlCoordinatorTests: XCTestCase {
    private func fixture(_ runtime: PreviewRuntime, execute: @escaping (CommandRequest) -> ProcessResult) -> AppCoordinator {
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources, execute: execute)
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, calendar: base.calendar, presetDevice: base.presetDevice))
        state.mediaVolumeKeysEnabled = true
        adb.ip = "192.0.2.1"
        state.connectionStatus = .connected("fake")
        state.seedSimulationReadings(volume: 10, muted: false)
        return state
    }

    func testVolumeFailuresReleaseBusyStateDoNotRetryAndAllowSameTargetAgain() async {
        // Read failure, failed keyevent, and a Binder write whose result cannot be confirmed.
        for failurePath in 0...2 {
            let runtime = PreviewRuntime()
            var fail = true
            var commands: [String] = []
            let state = fixture(runtime) { request in
                let command = request.arguments.last!
                commands.append(command)
                if fail {
                    if command.contains("audio 12"), failurePath != 2 {
                        return ProcessResult(output: "error: binder unavailable", exitCode: 1)
                    }
                    if (command.contains("audio 22") || command == "settings get system volume_music_speaker"), failurePath != 1 {
                        return ProcessResult(output: "", exitCode: 1)
                    }
                    if command.contains("keyevent") { return ProcessResult(output: "error: keyevent failed", exitCode: 1) }
                }
                return runtime.display.execute(request)
            }
            state.setDashboardVolume(27)
            XCTAssertEqual(state.dashboardVolume, 27) // Immediate preview survives the asynchronous submission.
            await state.waitForPendingWork()
            XCTAssertNotEqual(state.mediaVolumeHardware, 27)
            XCTAssertFalse(state.mediaVolumeCommitInFlight)
            XCTAssertFalse(state.mediaVolumePending)
            XCTAssertNotNil(state.dashboardVolumeError)
            XCTAssertFalse(state.mediaVolumeFallbackLogged)
            let count = commands.count
            runtime.scheduler.advance(by: 3)
            await state.waitForPendingWork()
            XCTAssertEqual(commands.count, count) // No retry from preview/hardware disagreement.

            fail = false
            state.setDashboardVolume(27)
            await state.waitForPendingWork()
            XCTAssertEqual(state.mediaVolumeHardware, 27)
            XCTAssertNil(state.dashboardVolumeError)
            XCTAssertFalse(state.mediaVolumeCommitInFlight)
            XCTAssertGreaterThan(commands.count, count)
        }
    }

    func testNewInputDuringFailedCommitIsNotSwallowedEvenAtTheSameTarget() async {
        let runtime = PreviewRuntime()
        var writes = 0
        var keyevents = 0
        let state = fixture(runtime) { request in
            let command = request.arguments.last!
            if command.contains("audio 12") { writes += 1; return ProcessResult(output: "error: binder unavailable", exitCode: 1) }
            if command.contains("keyevent") {
                keyevents += 1
                return ProcessResult(output: keyevents == 1 ? "error: first write failed" : "", exitCode: keyevents == 1 ? 1 : 0)
            }
            return runtime.display.execute(request)
        }
        state.deviceQueue.suspend()
        state.setDashboardVolume(27)
        state.setDashboardVolume(27)
        state.deviceQueue.resume()
        await state.waitForPendingWork()
        XCTAssertTrue(state.mediaVolumePending)
        XCTAssertEqual(state.mediaVolumePreview, 27)
        runtime.scheduler.advance(by: 0.2)
        await state.waitForPendingWork()
        XCTAssertEqual(keyevents, 2)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(state.mediaVolumeHardware, 27)
        XCTAssertFalse(state.mediaVolumePending)
        XCTAssertNil(state.dashboardVolumeError)
        let completedCount = keyevents
        runtime.scheduler.advance(by: 3)
        await state.waitForPendingWork()
        XCTAssertEqual(keyevents, completedCount)
    }

    func testRapidVolumeInputsKeepImmediateAndTrailingBinderCommits() async {
        let runtime = PreviewRuntime()
        var commands: [String] = []
        let state = fixture(runtime) { request in
            commands.append(request.arguments.last!)
            return runtime.display.execute(request)
        }
        state.deviceQueue.suspend()
        state.setDashboardVolume(11)
        state.setDashboardVolume(12)
        state.setDashboardVolume(13)
        XCTAssertEqual(state.dashboardVolume, 13)
        state.deviceQueue.resume()
        await state.waitForPendingWork()
        XCTAssertEqual(state.mediaVolumeHardware, 11)
        XCTAssertEqual(state.mediaVolumePreview, 13)
        runtime.scheduler.advance(by: 0.2)
        await state.waitForPendingWork()
        XCTAssertEqual(state.mediaVolumeHardware, 13)
        XCTAssertEqual(runtime.display.volume, 13)
        XCTAssertEqual(commands.filter { $0.contains("audio 12") }.count, 2)
        XCTAssertEqual(commands.filter { $0.contains("audio 22") }.count, 1)
    }

    func testCancelledCommitReleasesBusyStateWithoutSendingCommands() async {
        let runtime = PreviewRuntime()
        let state = fixture(runtime, execute: runtime.display.execute)
        state.deviceQueue.suspend()
        state.setDashboardVolume(27)
        state.adb.cancelSession()
        state.deviceQueue.resume()
        await state.waitForPendingWork()
        XCTAssertFalse(state.mediaVolumeCommitInFlight)
        XCTAssertFalse(state.mediaVolumePending)
        XCTAssertNotEqual(state.mediaVolumeHardware, 27)
        XCTAssertNotNil(state.dashboardVolumeError)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        state.adb.resumeSession()
        state.setDashboardVolume(27)
        await state.waitForPendingWork()
        XCTAssertEqual(state.mediaVolumeHardware, 27)
    }

    func testUnmuteFailureDoesNotCompleteVolumeAndCanBeRetried() async {
        let runtime = PreviewRuntime()
        var failMute = true
        var volumeWrites = 0
        let state = fixture(runtime) { request in
            let command = request.arguments.last!
            if command.contains("audio 12") { volumeWrites += 1 }
            if failMute && (command.contains("audio 17") || command.contains("audio 10")) {
                return ProcessResult(output: "error: mute unavailable", exitCode: 1)
            }
            return runtime.display.execute(request)
        }
        state.seedSimulationReadings(volume: 10, muted: true)
        state.setDashboardVolume(27)
        await state.waitForPendingWork()
        XCTAssertEqual(volumeWrites, 0)
        XCTAssertNotEqual(state.mediaVolumeHardware, 27)
        XCTAssertTrue(state.dashboardVolumeError?.contains("解除静音失败") == true)
        XCTAssertFalse(state.mediaVolumeCommitInFlight)
        XCTAssertTrue(state.mediaVolumeNeedsUnmute)
        failMute = false
        state.setDashboardVolume(27)
        await state.waitForPendingWork()
        XCTAssertEqual(state.mediaVolumeHardware, 27)
        XCTAssertNil(state.dashboardVolumeError)
        XCTAssertFalse(state.mediaVolumeNeedsUnmute)
    }

    func testMuteCallersReportFailuresAndUnknownStateNeverDefaultsToUnmuted() async {
        for action in 0...2 {
            let runtime = PreviewRuntime()
            var commands: [String] = []
            let state = fixture(runtime) { request in
                let command = request.arguments.last!
                commands.append(command)
                if command.contains("audio 17") { return ProcessResult(output: "", exitCode: 1) }
                return runtime.display.execute(request)
            }
            if action == 0 { state.applyMediaMute(true) }
            if action == 1 { state.toggleDashboardMute() }
            if action == 2 { state.mediaVolumeMuted = nil; state.toggleMediaMute() }
            await state.waitForPendingWork()
            XCTAssertNotNil(state.dashboardVolumeError)
            XCTAssertNil(state.dashboardMuted)
            XCTAssertFalse(commands.contains { $0.contains("keyevent") })
            if action != 0 { XCTAssertFalse(commands.contains { $0.contains("audio 10") }) }
        }
    }

    func testRapidDashboardMuteClicksStillToggleTwiceWithImmediatePreview() async {
        let runtime = PreviewRuntime()
        let state = fixture(runtime, execute: runtime.display.execute)
        state.deviceQueue.suspend()
        state.toggleDashboardMute()
        XCTAssertEqual(state.dashboardMuted, true)
        state.toggleDashboardMute()
        XCTAssertEqual(state.dashboardMuted, false)
        state.deviceQueue.resume()
        await state.waitForPendingWork()
        XCTAssertFalse(runtime.display.muted)
        XCTAssertEqual(state.dashboardMuted, false)
        XCTAssertNil(state.dashboardVolumeError)
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 10") }.count, 2)
    }
}
