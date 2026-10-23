import Foundation
import XCTest
import ToolboxConcurrency
import ToolboxDomain
import MimonitorPresetCore
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor final class IdentityConnectionTests: XCTestCase {
    private let serial = "000IdentityUSB"
    private let legacy = Data("{ \"presets\": [], \"tasks\": [], \"baseline\": { \"deviceIdentity\": \"192.0.2.7\", \"values\": {\"picture_contrast\":\"51\"} } }".utf8)

    private func fixture(_ runtime: PreviewRuntime = PreviewRuntime(), property: String? = nil,
                         intercept: ((CommandRequest) -> ProcessResult?)? = nil) -> (AppCoordinator, PreviewRuntime) {
        runtime.display.configureDiscovery(rows: "\(serial) device usb:fixture model:MiTV_Fixture")
        let base = runtime.environment()
        let adb = AdbClient(resources: base.adb.resources) { request in
            if let response = intercept?(request) { return response }
            if let property, request.arguments.last?.hasPrefix("getprop ro.") == true,
               request.arguments.last != "getprop ro.product.model" {
                return ProcessResult(output: property, exitCode: 0)
            }
            return runtime.display.execute(request)
        }
        return (AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, calendar: base.calendar, presetDevice: base.presetDevice)), runtime)
    }
    private func connect(_ state: AppCoordinator, usb: Bool = true) async {
        if usb { state.connectUSB(serial: serial) }
        else { state.setConnectionMode(.tcp); state.ipInput = "192.0.2.7"; state.connect() }
        await state.waitForPendingWork()
    }
    private func confirm(_ state: AppCoordinator, memories: Bool = false) async throws {
        state.confirmConnectionOwnership(includeMemories: memories, expectedSessionID: try XCTUnwrap(state.connection.identitySessionID))
        await state.waitForPendingWork()
    }

    func testFirstTCPAndUSBConnectionReadIdentityWithoutSavingOrDeploying() async {
        for usb in [false, true] {
            let runtime = PreviewRuntime(); runtime.preferences.set(legacy, forKey: "picture_presets_v1")
            runtime.preferences.set(" 192.0.2.99 ", forKey: "saved_ip")
            let (state, _) = fixture(runtime); await connect(state, usb: usb)
            XCTAssertTrue(state.isConnected); XCTAssertNotNil(state.connection.identityEvidence)
            XCTAssertTrue(state.connection.identityRestricted); XCTAssertNil(state.connection.presetIdentityKey)
            XCTAssertFalse(state.connection.allowsIdentityAutomaticActions)
            XCTAssertFalse(state.connection.memoryOwnershipConfirmed)
            XCTAssertEqual(runtime.preferences.data(forKey: "picture_presets_v1"), legacy)
            XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), " 192.0.2.99 ")
            XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1"))
            XCTAssertEqual(runtime.connectionBackupCount, 0)
            let target = usb ? serial : "192.0.2.7:5555"
            XCTAssertEqual(Array(runtime.display.recordedCommands.suffix(2)), [
                "-s \(target) shell getprop ro.serialno", "-s \(target) shell getprop ro.boot.serialno"])
            XCTAssertFalse(runtime.display.recordedCommands.contains { $0.contains("push ") || $0.contains("settings put") || $0.contains("preset.apply") })
            state.stop()
        }
    }

    func testExplicitSaveMirrorsOnlyDefaultTCPAndDoesNotConnect() async {
        for port in ["5555", "5566"] {
            let runtime = PreviewRuntime(); runtime.preferences.set("old.example", forKey: "saved_ip")
            let (state, _) = fixture(runtime); state.ipInput = "192.0.2.7"; state.connection.tcpPortInput = port
            state.saveConnectionPreference(); await state.waitForPendingWork()
            XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), port == "5555" ? "192.0.2.7" : "old.example")
            XCTAssertEqual(state.presetWorker.connectionProfileSnapshot().profile?.selectedEndpoint?.tcpPort, UInt16(port))
            XCTAssertEqual(runtime.connectionBackupCount, 1); XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
            XCTAssertFalse(state.isConnected); state.stop()
        }
    }

    func testBindingUsesOneLegacyKeyAcrossUSBAndTCPWithoutReencodingBaseline() async throws {
        let runtime = PreviewRuntime(); runtime.preferences.set(legacy, forKey: "picture_presets_v1")
        let (state, _) = fixture(runtime); await connect(state)
        let before = runtime.display.recordedCommands
        try await confirm(state)
        XCTAssertEqual(runtime.display.recordedCommands, before)
        XCTAssertEqual(state.connection.presetIdentityKey, "192.0.2.7")
        XCTAssertFalse(state.connection.memoryOwnershipConfirmed)
        let bound = try XCTUnwrap(state.presetWorker.connectionProfileSnapshot().profile)
        await connect(state, usb: false)
        XCTAssertFalse(state.connection.identityRestricted)
        XCTAssertEqual(state.connection.presetIdentityKey, "192.0.2.7")
        try await confirm(state)
        let profile = try XCTUnwrap(state.presetWorker.connectionProfileSnapshot().profile)
        XCTAssertEqual(profile.devices.count, 1); XCTAssertEqual(profile.devices[0].deviceID, bound.devices[0].deviceID)
        XCTAssertEqual(profile.devices[0].endpoints.count, 2)
        XCTAssertEqual(runtime.preferences.data(forKey: "picture_presets_v1"), legacy)
        XCTAssertEqual(state.presetConfiguration.baseline?.values, ["picture_contrast": "51"])
        state.stop()
    }

    func testGlobalMemoriesRequireSeparateConfirmationAndBindingDoesNotApplyThem() async throws {
        let runtime = PreviewRuntime()
        runtime.preferences.set(true, forKey: "hdr_sdr_local_dimming_enabled")
        runtime.preferences.set(true, forKey: "freesync_mode_memory_enabled")
        let (state, _) = fixture(runtime); await connect(state)
        let before = runtime.display.recordedCommands
        try await confirm(state)
        XCTAssertFalse(state.effectiveHdrMemoryEnabled)
        try await confirm(state, memories: true)
        XCTAssertTrue(state.connection.memoryOwnershipConfirmed)
        XCTAssertTrue(state.effectiveHdrMemoryEnabled)
        XCTAssertEqual(runtime.display.recordedCommands, before)
        XCTAssertTrue(state.hdrMemoryEnabled); XCTAssertTrue(state.freesyncMemoryEnabled)
        state.stop()
    }

    func testUnknownConfirmationIsSessionOnlyIdempotentAndUsesCanonicalNamespace() async throws {
        let (state, runtime) = fixture(property: "unknown\n"); await connect(state)
        XCTAssertNil(state.connection.identityEvidence)
        try await confirm(state, memories: true)
        let key = try XCTUnwrap(state.connection.presetIdentityKey)
        XCTAssertEqual(key, key.lowercased()); XCTAssertTrue(key.hasPrefix("device:"))
        XCTAssertFalse(state.connection.identityRestricted); XCTAssertFalse(state.connection.allowsIdentityAutomaticActions)
        XCTAssertFalse(state.connection.memoryOwnershipConfirmed)
        XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1"))
        try await confirm(state); XCTAssertEqual(state.connection.presetIdentityKey, key)
        await connect(state)
        XCTAssertTrue(state.connection.identityRestricted); XCTAssertNil(state.connection.presetIdentityKey)
        XCTAssertEqual(runtime.connectionBackupCount, 0); state.stop()
    }

    func testUnknownSessionPresetCanUpgradeLaterWithSameCompatibilityKey() async throws {
        let (state, runtime) = fixture(property: "unknown\n"); await connect(state); try await confirm(state)
        let key = try XCTUnwrap(state.connection.presetIdentityKey)
        state.createPreset(name: "Session preset"); await state.waitForPendingWork()
        XCTAssertEqual(state.presetConfiguration.baseline?.deviceIdentity, key)
        state.stop()
        let (restarted, _) = fixture(runtime); await connect(restarted)
        XCTAssertTrue(restarted.connection.identityRestricted)
        try await confirm(restarted)
        XCTAssertEqual(restarted.connection.presetIdentityKey, key)
        XCTAssertFalse(restarted.connection.identityRestricted); restarted.stop()
    }

    func testStaleConfirmationCannotBindNewSession() async throws {
        let (state, runtime) = fixture(); await connect(state)
        let old = try XCTUnwrap(state.connection.identitySessionID); await connect(state)
        state.confirmConnectionOwnership(includeMemories: true, expectedSessionID: old)
        await state.waitForPendingWork()
        XCTAssertTrue(state.connection.identityRestricted); XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1"))
        XCTAssertEqual(runtime.connectionBackupCount, 0); state.stop()
    }

    func testChangedLegacyOwnershipBeforeConfirmationFailsClosedAndPreservesBytes() async throws {
        let (state, runtime) = fixture(); await connect(state)
        runtime.preferences.set(legacy, forKey: "picture_presets_v1")
        try await confirm(state)
        XCTAssertFalse(state.isConnected); XCTAssertNil(state.adb.endpoint); XCTAssertTrue(state.connection.identityConflict)
        XCTAssertEqual(runtime.preferences.data(forKey: "picture_presets_v1"), legacy)
        XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1")); state.stop()
    }

    func testBadProfileAndMultipleOwnersCannotRetainExecutingEndpoint() async {
        for badProfile in [false, true] {
            let runtime = PreviewRuntime()
            if badProfile { runtime.preferences.set(Data("broken".utf8), forKey: "connection_profile_v1") }
            else { runtime.preferences.set(Data("{\"activeDeviceIdentity\":\"192.0.2.8\",\"baseline\":{\"deviceIdentity\":\"192.0.2.7\",\"values\":{}}}".utf8), forKey: "picture_presets_v1") }
            let (state, _) = fixture(runtime); await connect(state)
            XCTAssertFalse(state.isConnected); XCTAssertNil(state.adb.endpoint)
            XCTAssertTrue(state.connection.identityConflict); XCTAssertTrue(state.connection.identityRestricted)
            let before = runtime.display.recordedCommands
            state.createPreset(name: "blocked"); state.setLocalDimming(2); state.checkAutomaticTasks()
            await state.waitForPendingWork(); XCTAssertEqual(runtime.display.recordedCommands, before)
            state.stop()
        }
    }

    func testPersistedBindingMustBeRevalidatedAndIPReuseIsConflict() async throws {
        let (state, runtime) = fixture(); await connect(state, usb: false); try await confirm(state)
        let bytes = runtime.preferences.data(forKey: "connection_profile_v1"); state.stop()
        let (restarted, _) = fixture(runtime, property: "DIFFERENT-DEVICE\n")
        XCTAssertTrue(restarted.connection.identityRestricted); XCTAssertNil(restarted.connection.identityEvidence)
        restarted.autoConnectOnStartup(); await restarted.waitForPendingWork()
        XCTAssertFalse(restarted.isConnected); XCTAssertNil(restarted.adb.endpoint); XCTAssertTrue(restarted.connection.identityConflict)
        XCTAssertEqual(runtime.preferences.data(forKey: "connection_profile_v1"), bytes); restarted.stop()
    }

    func testPropertyFailureKeepsSavedBindingButDoesNotGrantItsCapabilities() async throws {
        let (state, runtime) = fixture(); await connect(state); try await confirm(state, memories: true)
        let bytes = runtime.preferences.data(forKey: "connection_profile_v1"); state.stop()
        let (restarted, _) = fixture(runtime, property: "unknown\n"); await connect(restarted)
        XCTAssertTrue(restarted.isConnected); XCTAssertTrue(restarted.connection.identityRestricted)
        XCTAssertFalse(restarted.connection.allowsIdentityAutomaticActions)
        XCTAssertFalse(restarted.connection.memoryOwnershipConfirmed)
        XCTAssertEqual(runtime.preferences.data(forKey: "connection_profile_v1"), bytes); restarted.stop()
    }

    func testLateIdentityReadCannotReviveDisconnectedSession() async {
        let began = expectation(description: "identity read began"), release = DispatchSemaphore(value: 0)
        let (state, runtime) = fixture(intercept: { request in
            guard request.arguments.last == "getprop ro.serialno" else { return nil }
            began.fulfill(); _ = release.wait(timeout: .now() + 3)
            return ProcessResult(output: "LATE-STABLE\n", exitCode: 0)
        })
        state.connectUSB(serial: serial)
        await fulfillment(of: [began], timeout: 3)
        state.disconnectAdb(); release.signal(); await state.waitForPendingWork()
        XCTAssertFalse(state.isConnected); XCTAssertNil(state.adb.endpoint); XCTAssertNil(state.connection.identityEvidence)
        XCTAssertNil(runtime.preferences.object(forKey: "connection_profile_v1")); state.stop()
    }

    func testPureLocalTaskEditsRemainAvailableWithoutIdentityOrDeviceCommands() async {
        let (state, runtime) = fixture()
        state.saveAutomaticTask(ScheduledPresetTask(id: "local", presetID: PicturePreset.baselineID, start: "10:00", end: "11:00", enabled: false))
        await state.waitForPendingWork()
        XCTAssertEqual(state.presetConfiguration.tasks.map(\.id), ["local"])
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
        XCTAssertTrue(state.connection.identityRestricted); state.stop()
    }
}
