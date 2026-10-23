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

    func testOldPollCannotReplaceNewVolumePreviewOrTrailingTarget() async {
        for nativeVolumeKey in [false, true] {
            let runtime = PreviewRuntime()
            runtime.display.volume = 4
            runtime.display.muted = true
            let pollRead = expectation(description: "old poll readings captured")
            let firstWriteStarted = expectation(description: "poll published; first volume write held")
            let releasePoll = DispatchSemaphore(value: 0)
            let releaseFirstWrite = DispatchSemaphore(value: 0)
            defer { releasePoll.signal(); releaseFirstWrite.signal() }
            var muteReads = 0
            var targets: [Int] = [] // Confined to the worker until a barrier or completion.
            let state = fixture(runtime) { request in
                let command = request.arguments.last!
                if command.contains("audio 12") {
                    targets.append(Int(command.split(separator: " ")[7])!)
                    if targets.count == 1 {
                        // The poll's MainActor publication is queued before this marker.
                        DispatchQueue.main.async { firstWriteStarted.fulfill() }
                        XCTAssertEqual(releaseFirstWrite.wait(timeout: .now() + 5), .success)
                    }
                }
                let result = runtime.display.execute(request)
                if command.contains("audio 17") {
                    muteReads += 1
                    if muteReads == 1 {
                        DispatchQueue.main.async { pollRead.fulfill() }
                        XCTAssertEqual(releasePoll.wait(timeout: .now() + 5), .success)
                    }
                }
                return result
            }
            state.seedSimulationReadings(volume: 10, muted: true)
            state.mediaVolumeNativeOSD = false
            state.mediaVolumeStep = 5
            state.refreshMediaVolumeState()
            await fulfillment(of: [pollRead], timeout: 3)

            let first = nativeVolumeKey ? 15 : 27
            let latest = nativeVolumeKey ? 20 : 39
            if nativeVolumeKey {
                state.adjustMediaVolume(increase: true)
                state.adjustMediaVolume(increase: true)
            } else {
                state.setDashboardVolume(first)
                state.setDashboardVolume(latest)
            }
            XCTAssertEqual(state.mediaVolumePreview, latest)
            XCTAssertEqual(state.dashboardVolume, latest)
            releasePoll.signal()
            await fulfillment(of: [firstWriteStarted], timeout: 3)
            XCTAssertEqual(state.mediaVolumePreview, latest)
            XCTAssertEqual(state.mediaVolumeHardware, 10)
            XCTAssertEqual(state.dashboardVolume, latest)
            XCTAssertEqual(state.currentValues["volume_music_speaker"], String(latest))
            XCTAssertEqual(state.mediaVolumeMuted, false)
            XCTAssertEqual(state.dashboardMuted, false)
            XCTAssertTrue(state.mediaVolumePending)
            XCTAssertTrue(state.mediaVolumeCommitInFlight)

            releaseFirstWrite.signal()
            await state.waitForPendingWork()
            XCTAssertEqual(state.mediaVolumeHardware, first)
            XCTAssertEqual(state.mediaVolumePreview, latest)
            XCTAssertTrue(state.mediaVolumePending)
            runtime.scheduler.advance(by: 0.2)
            await state.waitForPendingWork()
            XCTAssertEqual(targets, [first, latest])
            XCTAssertEqual(runtime.display.volume, latest)
            XCTAssertFalse(runtime.display.muted)
            XCTAssertEqual(state.mediaVolumeHardware, latest)
            XCTAssertEqual(state.dashboardVolume, latest)
            XCTAssertFalse(state.mediaVolumePending)
            XCTAssertFalse(state.mediaVolumeCommitInFlight)
            XCTAssertNil(state.dashboardVolumeError)
            let count = runtime.display.recordedCommands.count
            runtime.scheduler.advance(by: 3)
            await state.waitForPendingWork()
            XCTAssertEqual(runtime.display.recordedCommands.count, count)
        }
    }

    func testOldPollCannotReplaceNewMuteIntentWithoutVolumeCommitFlags() async {
        for nativeMuteKey in [false, true] {
            for initiallyMuted in [false, true] {
                let runtime = PreviewRuntime()
                runtime.display.muted = initiallyMuted
                let pollRead = expectation(description: "old mute reading captured")
                let muteWriteStarted = expectation(description: "poll published; mute write held")
                let releasePoll = DispatchSemaphore(value: 0)
                let releaseMuteWrite = DispatchSemaphore(value: 0)
                defer { releasePoll.signal(); releaseMuteWrite.signal() }
                var muteReads = 0
                let state = fixture(runtime) { request in
                    let command = request.arguments.last!
                    if command.contains("audio 10") {
                        DispatchQueue.main.async { muteWriteStarted.fulfill() }
                        XCTAssertEqual(releaseMuteWrite.wait(timeout: .now() + 5), .success)
                    }
                    let result = runtime.display.execute(request)
                    if command.contains("audio 17") {
                        muteReads += 1
                        if muteReads == 1 {
                            DispatchQueue.main.async { pollRead.fulfill() }
                            XCTAssertEqual(releasePoll.wait(timeout: .now() + 5), .success)
                        }
                    }
                    return result
                }
                state.seedSimulationReadings(volume: 10, muted: initiallyMuted)
                state.refreshMediaVolumeState()
                await fulfillment(of: [pollRead], timeout: 3)
                if nativeMuteKey { state.toggleMediaMute() }
                else { state.toggleDashboardMute() }
                XCTAssertEqual(state.dashboardMuted, !initiallyMuted)
                XCTAssertFalse(state.mediaVolumePending)
                XCTAssertFalse(state.mediaVolumeCommitInFlight)
                releasePoll.signal()
                await fulfillment(of: [muteWriteStarted], timeout: 3)
                // These volume-only guards cannot distinguish a stale mute poll.
                XCTAssertFalse(state.mediaVolumePending)
                XCTAssertFalse(state.mediaVolumeCommitInFlight)
                XCTAssertEqual(state.mediaVolumeMuted, !initiallyMuted)
                XCTAssertEqual(state.dashboardMuted, !initiallyMuted)
                XCTAssertNil(state.dashboardVolumeError)
                releaseMuteWrite.signal()
                await state.waitForPendingWork()
                XCTAssertEqual(runtime.display.muted, !initiallyMuted)
                XCTAssertEqual(state.mediaVolumeMuted, !initiallyMuted)
                XCTAssertEqual(state.dashboardMuted, !initiallyMuted)
                XCTAssertNil(state.dashboardVolumeError)
                XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 10") }.count, 1)
                XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("audio 12") })
            }
        }
    }

    func testPollAcceptsExternalVolumeAndMuteChangesWithoutCreatingUserIntent() async {
        let runtime = PreviewRuntime()
        let state = fixture(runtime, execute: runtime.display.execute)
        let intent = state.mediaMuteIntent
        for (volume, muted) in [(38, true), (71, false)] {
            runtime.display.volume = volume
            runtime.display.muted = muted
            state.refreshMediaVolumeState()
            await state.waitForPendingWork()
            XCTAssertEqual(state.mediaVolumePreview, volume)
            XCTAssertEqual(state.mediaVolumeHardware, volume)
            XCTAssertEqual(state.dashboardVolume, volume)
            XCTAssertEqual(state.mediaVolumeMuted, muted)
            XCTAssertEqual(state.dashboardMuted, muted)
            XCTAssertEqual(state.mediaMuteIntent, intent)
            XCTAssertFalse(state.mediaVolumePending)
            XCTAssertFalse(state.mediaVolumeCommitInFlight)
            XCTAssertNil(state.dashboardVolumeError)
        }
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 22") }.count, 2)
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 17") }.count, 2)
        XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("audio 12") || $0.contains("audio 10") })
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

    func testNativeMuteInterleavingKeepsThreeDistinctToggleTargets() async {
        let runtime = PreviewRuntime()
        let secondWriteStarted = expectation(description: "A published; B held in executor")
        let releaseSecondWrite = DispatchSemaphore(value: 0)
        defer { releaseSecondWrite.signal() }
        var targets: [Bool] = [] // Only read after the worker barrier or completion.
        let state = fixture(runtime) { request in
            let command = request.arguments.last!
            if command.contains("audio 10") {
                targets.append(command.contains("i32 -100"))
                if targets.count == 2 {
                    // A queues its MainActor publication before this serial worker starts B.
                    // The main-queue marker therefore runs after A's callback, with B blocked.
                    DispatchQueue.main.async { secondWriteStarted.fulfill() }
                    XCTAssertEqual(releaseSecondWrite.wait(timeout: .now() + 5), .success)
                }
            }
            return runtime.display.execute(request)
        }
        state.deviceQueue.suspend()
        state.toggleMediaMute() // A: true
        state.toggleMediaMute() // B: false
        XCTAssertEqual(state.mediaVolumeMuted, false)
        state.deviceQueue.resume()
        await fulfillment(of: [secondWriteStarted], timeout: 3)
        XCTAssertEqual(state.mediaVolumeMuted, false)
        XCTAssertEqual(state.dashboardMuted, false)
        state.toggleMediaMute() // C must derive true from B's preview, not A's completion.
        XCTAssertEqual(state.mediaVolumeMuted, true)
        releaseSecondWrite.signal()
        await state.waitForPendingWork()
        XCTAssertEqual(targets, [true, false, true])
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 17") }.count, 1)
        XCTAssertTrue(runtime.display.muted)
        XCTAssertEqual(state.mediaVolumeMuted, true)
        XCTAssertEqual(state.dashboardMuted, true)
        XCTAssertNil(state.dashboardVolumeError)
    }

    func testOldMuteFailureDoesNotClearNewerPreviewOrErrorState() async {
        let runtime = PreviewRuntime()
        let secondWriteStarted = expectation(description: "A failure published; B held in executor")
        let releaseSecondWrite = DispatchSemaphore(value: 0)
        defer { releaseSecondWrite.signal() }
        var writes = 0
        let state = fixture(runtime) { request in
            let command = request.arguments.last!
            if command.contains("audio 10") {
                writes += 1
                if writes == 2 {
                    DispatchQueue.main.async { secondWriteStarted.fulfill() }
                    XCTAssertEqual(releaseSecondWrite.wait(timeout: .now() + 5), .success)
                }
            }
            // A's Binder write can succeed, but its first verification cannot confirm it.
            if command.contains("audio 17"), writes == 1 { return ProcessResult(output: "", exitCode: 1) }
            return runtime.display.execute(request)
        }
        state.deviceQueue.suspend()
        state.toggleMediaMute()
        state.toggleMediaMute()
        state.deviceQueue.resume()
        await fulfillment(of: [secondWriteStarted], timeout: 3)
        XCTAssertEqual(state.mediaVolumeMuted, false)
        XCTAssertEqual(state.dashboardMuted, false)
        XCTAssertNil(state.dashboardVolumeError) // B's current error state must survive A's failure.
        releaseSecondWrite.signal()
        await state.waitForPendingWork()
        XCTAssertFalse(runtime.display.muted)
        XCTAssertEqual(state.dashboardMuted, false)
        XCTAssertNil(state.dashboardVolumeError)
        XCTAssertEqual(runtime.display.recordedCommands.filter { $0.contains("audio 22") }.count, 0)
    }

    func testOldMuteCompletionCannotOverrideLaterVolumeUnmuteIntent() async {
        for failFirstRead in [false, true] {
            for nativeVolumeKey in [false, true] {
                let runtime = PreviewRuntime()
                let unmuteStarted = expectation(description: "old mute completed; volume unmute held")
                let releaseUnmute = DispatchSemaphore(value: 0)
                defer { releaseUnmute.signal() }
                var muteWrites = 0
                let state = fixture(runtime) { request in
                    let command = request.arguments.last!
                    if command.contains("audio 10") {
                        muteWrites += 1
                        if muteWrites == 2 {
                            DispatchQueue.main.async { unmuteStarted.fulfill() }
                            XCTAssertEqual(releaseUnmute.wait(timeout: .now() + 5), .success)
                        }
                    }
                    if failFirstRead, command.contains("audio 17"), muteWrites == 1 {
                        return ProcessResult(output: "", exitCode: 1)
                    }
                    return runtime.display.execute(request)
                }
                state.deviceQueue.suspend()
                state.toggleMediaMute()
                if nativeVolumeKey { state.adjustMediaVolume(increase: true) }
                else { state.setDashboardVolume(27) }
                state.deviceQueue.resume()
                await fulfillment(of: [unmuteStarted], timeout: 3)
                XCTAssertEqual(state.mediaVolumeMuted, false)
                XCTAssertEqual(state.dashboardMuted, false)
                XCTAssertNil(state.dashboardVolumeError)
                releaseUnmute.signal()
                await state.waitForPendingWork()
                XCTAssertFalse(runtime.display.muted)
                XCTAssertEqual(state.dashboardMuted, false)
                XCTAssertNil(state.dashboardVolumeError)
            }
        }
    }
}
