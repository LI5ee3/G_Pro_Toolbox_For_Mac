import CryptoKit
import Foundation
import Synchronization
import XCTest
import ToolboxDomain
@testable import MimonitorPresetCore

private final class ProfilePreferences: PreferencesStore {
    var values: [String: Any]
    var writes: [String] = []
    var write: ((Any?, String) -> Bool)?
    init(_ values: [String: Any] = [:]) { self.values = values }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        writes.append(key)
        if write?(value, key) ?? true { values[key] = value }
    }
    func removeObject(forKey key: String) { set(nil, forKey: key) }
    func register(defaults: [String: Any]) { for (key, value) in defaults where values[key] == nil { values[key] = value } }
}

private struct ProfileTestDevice: PresetDevice {
    var identity: String { "192.0.2.7" }
    func capture() throws -> [String: String] { ["brightness": "41"] }
    func apply(_ values: [String: String]) throws -> PresetApplyReport { .init(applied: ["brightness"]) }
}

final class ConnectionProfileStoreTests: XCTestCase {
    private let legacy = Data("{\n  \"baseline\": {\"deviceIdentity\":\"192.0.2.7\",\"values\":{\"brightness\":\"41\"}},\"applicationIncomplete\":true\n}".utf8)
    private let tcp = AdbEndpoint.tcp(host: "192.0.2.7")!
    private func usb(_ serial: String = "USB_A") -> AdbEndpoint {
        guard case .complete(let list) = AdbDeviceListParser.parse("List of devices attached\n\(serial) device usb:1-1 product:test\n") else { fatalError("invalid fixture") }
        return AdbEndpoint.usb(discovered: list[0])!
    }
    private func evidence(_ endpoint: AdbEndpoint, _ stable: String = "PHYSICAL_A") -> IdentityEvidence {
        .init(endpoint: endpoint, sessionID: UUID(), sampledAt: Date(), stableIdentifier: stable,
              roSerialno: stable, roBootSerialno: stable)
    }
    private func bind(_ store: ConnectionProfileStore, endpoint: AdbEndpoint? = nil, stable: String = "PHYSICAL_A",
                      confirmed: Bool = true, memories: Bool = false,
                      backup: (Data, String) throws -> Void = { _, _ in }) throws -> ConnectionProfileSnapshot {
        try store.bind(evidence: evidence(endpoint ?? tcp, stable), expected: store.snapshot(),
            confirmLegacyOwnership: confirmed, confirmMemories: memories, backup: backup, validateCurrent: {})
    }
    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func testReadOnlyStartupPreservesLegacyBytesAndEveryPreference() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy, "saved_ip": "192.0.2.7", "hdr_memory": true])
        let snapshot = ConnectionProfileStore(preferences: preferences).snapshot()
        XCTAssertNil(snapshot.error); XCTAssertNil(snapshot.profile)
        XCTAssertEqual(snapshot.ownershipKeys, ["192.0.2.7"])
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), legacy)
        XCTAssertEqual(preferences.writes, [])
    }

    func testLegacyRequiresExplicitOwnershipThenBindsWithoutReencodingPresets() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy, "saved_ip": "192.0.2.7"])
        let store = ConnectionProfileStore(preferences: preferences)
        XCTAssertThrowsError(try bind(store, confirmed: false))
        XCTAssertEqual(preferences.writes, [])
        var packages: [(Data, String)] = []
        let snapshot = try bind(store, backup: { packages.append(($0, $1)) })
        let record = try XCTUnwrap(snapshot.profile?.devices.first)
        XCTAssertEqual(record.presetIdentityKey, "192.0.2.7")
        XCTAssertEqual(record.legacyAliases, ["192.0.2.7"])
        XCTAssertNil(snapshot.profile?.memoryOwnerDeviceID)
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), legacy)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].1, sha(packages[0].0))
        let package = try XCTUnwrap(PropertyListSerialization.propertyList(from: packages[0].0, format: nil) as? [String: Any])
        let original = try XCTUnwrap(package["rawSnapshotJSON"] as? Data)
        XCTAssertEqual(package["originalDigest"] as? String, sha(original))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertNotNil(raw["saved_ip"]); XCTAssertNotNil(raw["picture_presets_v1"]); XCTAssertNotNil(raw["connection_profile_v1"])
        XCTAssertEqual(ConnectionProfileStore(preferences: preferences).snapshot().profile, snapshot.profile)
    }

    func testRepeatedConfirmationIsNoOpWithoutNewUUIDRevisionOrBackup() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        var count = 0
        let first = try bind(store, backup: { _, _ in count += 1 })
        let writes = preferences.writes
        let second = try bind(store, backup: { _, _ in count += 1 })
        XCTAssertEqual(first.profile, second.profile); XCTAssertEqual(first.token, second.token)
        XCTAssertEqual(count, 1); XCTAssertEqual(preferences.writes, writes)
    }

    func testUSBAndTCPShareConfirmedLegacyKeyAndSingleBaseline() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy, "saved_ip": "192.0.2.7"])
        let store = ConnectionProfileStore(preferences: preferences)
        let first = try bind(store, endpoint: usb())
        let second = try bind(store)
        XCTAssertEqual(second.profile?.devices.count, 1)
        XCTAssertEqual(second.profile?.devices.first?.deviceID, first.profile?.devices.first?.deviceID)
        XCTAssertEqual(second.profile?.devices.first?.presetIdentityKey, "192.0.2.7")
        XCTAssertEqual(second.profile?.devices.first?.endpoints.count, 2)
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), legacy)
    }

    func testDifferentPhysicalDeviceCannotReuseBoundEndpointOrLegacyAlias() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        _ = try bind(store)
        let saved = preferences.data(forKey: "connection_profile_v1")
        XCTAssertThrowsError(try bind(store, stable: "PHYSICAL_B"))
        XCTAssertThrowsError(try bind(store, endpoint: usb(), stable: "PHYSICAL_B"))
        XCTAssertEqual(preferences.data(forKey: "connection_profile_v1"), saved)
    }

    func testTwoUSBSerialsWithSameStablePropertyAreConflict() throws {
        let preferences = ProfilePreferences()
        let store = ConnectionProfileStore(preferences: preferences)
        _ = try bind(store, endpoint: usb("USB_A"))
        XCTAssertThrowsError(try bind(store, endpoint: usb("USB_B")))
        XCTAssertEqual(store.snapshot().profile?.devices.first?.endpoints.count, 1)
    }

    func testMultipleLegacyOwnersAndReservedUnregisteredKeyCannotBeClaimed() throws {
        let cases = [Data("{\"baseline\":{\"deviceIdentity\":\"old-a\",\"values\":{}},\"activeDeviceIdentity\":\"old-b\"}".utf8),
                     Data("{\"activeDeviceIdentity\":\"device:not-a-uuid\"}".utf8)]
        for data in cases {
            let preferences = ProfilePreferences(["picture_presets_v1": data])
            XCTAssertThrowsError(try bind(ConnectionProfileStore(preferences: preferences)))
            XCTAssertEqual(preferences.writes, [])
        }
    }

    func testOldOptionalFieldsAndEmptyConfigurationGetOneNamespacedIdentity() throws {
        let data = Data("{\"presets\":[],\"tasks\":[]}".utf8)
        let preferences = ProfilePreferences(["picture_presets_v1": data])
        let store = ConnectionProfileStore(preferences: preferences)
        let first = try bind(store, confirmed: false)
        let record = try XCTUnwrap(first.profile?.devices.first)
        XCTAssertEqual(record.presetIdentityKey, "device:\(record.deviceID.uuidString.lowercased())")
        XCTAssertEqual(record.legacyAliases, [])
        XCTAssertEqual(try bind(store, confirmed: false).profile, first.profile)
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), data)
    }

    func testSessionOnlyNamespacedBaselineRequiresConfirmationBeforeStableUpgrade() throws {
        let id = UUID()
        let key = "device:\(id.uuidString.lowercased())"
        let original = Data("{\"baseline\":{\"deviceIdentity\":\"\(key)\",\"values\":{}}}".utf8)
        let preferences = ProfilePreferences(["picture_presets_v1": original])
        let store = ConnectionProfileStore(preferences: preferences)
        XCTAssertThrowsError(try bind(store, confirmed: false))
        let upgraded = try bind(store, confirmed: true)
        XCTAssertEqual(upgraded.profile?.devices.first?.deviceID, id)
        XCTAssertEqual(upgraded.profile?.devices.first?.presetIdentityKey, key)
        XCTAssertEqual(upgraded.profile?.devices.first?.legacyAliases, [])
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), original)
        XCTAssertEqual(ConnectionProfileStore(preferences: preferences).snapshot().profile, upgraded.profile)
    }

    func testNormalPresetContentChangesDoNotRevokeExistingIdentity() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        let first = try bind(store)
        preferences.values["picture_presets_v1"] = Data(String(decoding: legacy, as: UTF8.self).replacingOccurrences(of: "41", with: "56").utf8)
        let changed = store.snapshot()
        XCTAssertNil(changed.error); XCTAssertEqual(changed.ownershipKeys, ["192.0.2.7"])
        XCTAssertEqual(changed.profile, first.profile); XCTAssertNotEqual(changed.token, first.token)
        XCTAssertEqual(try bind(store).profile, first.profile)
    }

    func testOwnershipChangedDuringBackupStopsBeforeProfileWrite() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        let changed = Data("{\"activeDeviceIdentity\":\"another-owner\"}".utf8)
        XCTAssertThrowsError(try bind(store, backup: { _, _ in preferences.values["picture_presets_v1"] = changed }))
        XCTAssertNil(preferences.object(forKey: "connection_profile_v1"))
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), changed)
        XCTAssertEqual(preferences.writes, [])
    }

    func testOwnershipChangedDuringCommitPreservedAndOnlyOwnEnvelopeRolledBack() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        let changed = Data("{\"activeDeviceIdentity\":\"another-owner\"}".utf8)
        preferences.write = { value, key in
            if key == "connection_profile_v1", value != nil { preferences.values["picture_presets_v1"] = changed }
            return true
        }
        XCTAssertThrowsError(try bind(store))
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), changed)
        XCTAssertNil(preferences.object(forKey: "connection_profile_v1"))
        XCTAssertNotNil(store.snapshot().error)
    }

    func testBackupFailureNeverWritesAnyPreference() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        XCTAssertThrowsError(try bind(ConnectionProfileStore(preferences: preferences), backup: { _, _ in throw PresetError("disk full") }))
        XCTAssertEqual(preferences.writes, [])
    }

    func testLostEnvelopeWriteCannotActivateBindingAndRestartSeesNoBinding() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        preferences.write = { _, key in key != "connection_profile_v1" }
        XCTAssertThrowsError(try bind(store))
        XCTAssertNotNil(store.snapshot().error)
        XCTAssertNil(ConnectionProfileStore(preferences: preferences).snapshot().profile)
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), legacy)
    }

    func testMismatchedReadbackNeverOverwritesAnotherWriterAndRestartBlocksIt() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let corrupt = Data("incomplete-other-write".utf8)
        preferences.write = { _, key in
            if key == "connection_profile_v1" { preferences.values[key] = corrupt; return false }; return true
        }
        let store = ConnectionProfileStore(preferences: preferences)
        XCTAssertThrowsError(try bind(store))
        XCTAssertEqual(preferences.data(forKey: "connection_profile_v1"), corrupt)
        XCTAssertNotNil(ConnectionProfileStore(preferences: preferences).snapshot().error)
    }

    func testSessionInvalidatedAfterWriteRollsBackOwnBinding() {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy])
        let store = ConnectionProfileStore(preferences: preferences)
        var checks = 0
        XCTAssertThrowsError(try store.bind(evidence: evidence(tcp), expected: store.snapshot(),
            confirmLegacyOwnership: true, confirmMemories: false, backup: { _, _ in }, validateCurrent: {
                checks += 1; if checks == 3 { throw PresetError("session cancelled") }
            }))
        XCTAssertEqual(checks, 3)
        XCTAssertNil(preferences.object(forKey: "connection_profile_v1"))
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), legacy)
    }

    func testInvalidationBeforeBackupAndBeforeWriteLeavesOriginalStateOnRestart() {
        for cancellationCheck in [1, 2] {
            let preferences = ProfilePreferences(["picture_presets_v1": legacy])
            let store = ConnectionProfileStore(preferences: preferences)
            var checks = 0, backups = 0
            XCTAssertThrowsError(try store.bind(evidence: evidence(tcp), expected: store.snapshot(),
                confirmLegacyOwnership: true, confirmMemories: false,
                backup: { _, _ in backups += 1 }, validateCurrent: {
                    checks += 1; if checks == cancellationCheck { throw PresetError("cancelled") }
                }))
            XCTAssertEqual(backups, cancellationCheck - 1)
            XCTAssertEqual(preferences.writes, [])
            XCTAssertNil(ConnectionProfileStore(preferences: preferences).snapshot().profile)
        }
    }

    func testSingleWorkerSerializesPresetAndBindingAndRejectsStaleApproval() throws {
        let worker = PresetWorker(store: PresetStore(defaults: MemoryPreferences()))
        let expected = worker.connectionProfileSnapshot(), identity = evidence(tcp)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let presetDone = DispatchSemaphore(value: 0), bindingStarted = DispatchSemaphore(value: 0), bindingDone = DispatchSemaphore(value: 0)
        let results = Mutex((presetError: false, bindingFailed: false, backups: 0))
        DispatchQueue.global().async {
            do {
                _ = try worker.withEngine { engine in
                    entered.signal(); release.wait()
                    return try engine.create(name: "ordinary edit", device: ProfileTestDevice())
                }
            } catch { results.withLock { $0.presetError = true } }
            presetDone.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            bindingStarted.signal()
            do {
                _ = try worker.bindConnectionIdentity(evidence: identity, expected: expected,
                    confirmLegacyOwnership: true, backup: { _, _ in results.withLock { $0.backups += 1 } }, validateCurrent: {})
            } catch { results.withLock { $0.bindingFailed = true } }
            bindingDone.signal()
        }
        XCTAssertEqual(bindingStarted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(bindingDone.wait(timeout: .now() + 0.05), .timedOut)
        release.signal()
        XCTAssertEqual(presetDone.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(bindingDone.wait(timeout: .now() + 2), .success)
        results.withLock { XCTAssertFalse($0.presetError); XCTAssertTrue($0.bindingFailed); XCTAssertEqual($0.backups, 0) }
        XCTAssertEqual(worker.connectionProfileSnapshot().ownershipKeys, ["192.0.2.7"])
        XCTAssertNil(worker.connectionProfileSnapshot().profile)
    }

    func testMalformedFutureIncompleteAndWrongTypeProfilesAreReadOnlyErrors() throws {
        let seed = ProfilePreferences()
        let valid = try bind(ConnectionProfileStore(preferences: seed)).profile!
        var future = valid; future.schemaVersion = 2
        let cases: [Any] = [Data("{".utf8), try JSONEncoder().encode(future), Data("{\"schemaVersion\":1}".utf8), "unexpected-string"]
        for value in cases {
            let preferences = ProfilePreferences(["connection_profile_v1": value, "saved_ip": "192.0.2.7"])
            let store = ConnectionProfileStore(preferences: preferences)
            XCTAssertNotNil(store.snapshot().error)
            XCTAssertThrowsError(try bind(store))
            XCTAssertEqual(preferences.writes, [])
            XCTAssertEqual(preferences.string(forKey: "saved_ip"), "192.0.2.7")
        }
    }

    func testWrongTypeAndMalformedLegacyPresetsAreNeverOverwritten() {
        for value: Any in ["unexpected", Data("{".utf8)] {
            let preferences = ProfilePreferences(["picture_presets_v1": value])
            let store = ConnectionProfileStore(preferences: preferences)
            XCTAssertNotNil(store.snapshot().error)
            XCTAssertThrowsError(try bind(store)); XCTAssertEqual(preferences.writes, [])
        }
    }

    func testUSBAndNondefaultTCPPreferenceNeverMirrorSavedIP() throws {
        for endpoint in [usb(), AdbEndpoint.tcp(host: "192.0.2.9", port: 5566)!] {
            let preferences = ProfilePreferences(["saved_ip": "old-host"])
            let store = ConnectionProfileStore(preferences: preferences)
            let saved = try store.savePreference(endpoint: endpoint, expected: store.snapshot(), backup: { _, _ in }, validateCurrent: {})
            XCTAssertTrue(saved.profile!.selectedEndpoint!.matches(endpoint))
            XCTAssertEqual(preferences.string(forKey: "saved_ip"), "old-host")
            XCTAssertEqual(preferences.writes, ["connection_profile_v1"])
        }
    }

    func testMirrorFailureKeepsAuthoritativeEnvelopeWithWarning() throws {
        let preferences = ProfilePreferences(["saved_ip": "old-host"])
        preferences.write = { _, key in key != "saved_ip" }
        let store = ConnectionProfileStore(preferences: preferences)
        let saved = try store.savePreference(endpoint: tcp, expected: store.snapshot(), backup: { _, _ in }, validateCurrent: {})
        XCTAssertNil(saved.error); XCTAssertNotNil(saved.warning)
        XCTAssertTrue(saved.profile!.selectedEndpoint!.matches(tcp))
        XCTAssertEqual(preferences.string(forKey: "saved_ip"), "old-host")
        XCTAssertEqual(ConnectionProfileStore(preferences: preferences).snapshot().profile, saved.profile)
    }

    func testGlobalMemoriesHaveExactlyOneExplicitOwnerAndKeepSavedSwitches() throws {
        let preferences = ProfilePreferences(["hdr_memory": true, "freesync_memory": false])
        let store = ConnectionProfileStore(preferences: preferences)
        let a = try bind(store, memories: false).profile!.devices[0]
        XCTAssertNil(store.snapshot().profile?.memoryOwnerDeviceID)
        _ = try bind(store, memories: true)
        XCTAssertEqual(store.snapshot().profile?.memoryOwnerDeviceID, a.deviceID)
        let bEndpoint = AdbEndpoint.tcp(host: "192.0.2.8")!
        _ = try bind(store, endpoint: bEndpoint, stable: "PHYSICAL_B")
        XCTAssertEqual(store.snapshot().profile?.memoryOwnerDeviceID, a.deviceID)
        let b = try bind(store, endpoint: bEndpoint, stable: "PHYSICAL_B", memories: true).profile!.devices[1]
        XCTAssertEqual(store.snapshot().profile?.memoryOwnerDeviceID, b.deviceID)
        XCTAssertTrue(preferences.bool(forKey: "hdr_memory")); XCTAssertFalse(preferences.bool(forKey: "freesync_memory"))
    }

    func testBackupPreservesAbsentAndNonStringLegacyPreferenceTypes() throws {
        let preferences = ProfilePreferences(["saved_ip": ["old", 42, true, Data([1, 2, 3])] as [Any]])
        let store = ConnectionProfileStore(preferences: preferences)
        var backupData: Data?
        _ = try bind(store, endpoint: usb(), backup: { data, _ in backupData = data })
        let package = try XCTUnwrap(PropertyListSerialization.propertyList(from: XCTUnwrap(backupData), format: nil) as? [String: Any])
        let original = try XCTUnwrap(package["rawSnapshotJSON"] as? Data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        XCTAssertNotNil((raw["saved_ip"] as? [String: Any])?["array"])
        XCTAssertNotNil((raw["picture_presets_v1"] as? [String: Any])?["absent"])
        XCTAssertNotNil((raw["connection_profile_v1"] as? [String: Any])?["absent"])
        XCTAssertEqual(preferences.writes, ["connection_profile_v1"])
    }

    func testRollbackRestoresOnlyNewKeyAndPreservesLaterLegacyEdits() throws {
        let preferences = ProfilePreferences(["picture_presets_v1": legacy, "saved_ip": "old-host"])
        let store = ConnectionProfileStore(preferences: preferences)
        var original: Data?
        _ = try bind(store, backup: { data, _ in original = data })
        preferences.values["saved_ip"] = "later-host"
        let later = Data("{\"activeDeviceIdentity\":\"later-owner\"}".utf8)
        preferences.values["picture_presets_v1"] = later
        var backupCount = 0
        let result = try store.restore(backupData: XCTUnwrap(original), expected: store.snapshot(),
            backup: { _, _ in backupCount += 1 }, validateCurrent: {})
        XCTAssertNil(result.profile); XCTAssertEqual(backupCount, 1)
        XCTAssertEqual(preferences.string(forKey: "saved_ip"), "later-host")
        XCTAssertEqual(preferences.data(forKey: "picture_presets_v1"), later)
    }

    func testRollbackRejectsStaleSnapshotAndDamagedBackup() throws {
        let preferences = ProfilePreferences()
        let store = ConnectionProfileStore(preferences: preferences)
        var original: Data?
        let saved = try bind(store, backup: { data, _ in original = data })
        preferences.values["saved_ip"] = "later-host"
        XCTAssertThrowsError(try store.restore(backupData: XCTUnwrap(original), expected: saved, backup: { _, _ in }, validateCurrent: {}))
        XCTAssertThrowsError(try store.restore(backupData: Data("damaged".utf8), expected: store.snapshot(), backup: { _, _ in }, validateCurrent: {}))
        XCTAssertNotNil(store.snapshot().profile)
    }

    func testPlaceholderAndConflictingStoredPropertyEvidenceAreRejected() {
        for (serial, boot) in [("unknown", "unknown"), ("PHYSICAL_A", "PHYSICAL_B")] {
            let preferences = ProfilePreferences()
            let store = ConnectionProfileStore(preferences: preferences)
            let evidence = IdentityEvidence(endpoint: tcp, sessionID: UUID(), sampledAt: Date(),
                stableIdentifier: serial, roSerialno: serial, roBootSerialno: boot)
            XCTAssertThrowsError(try store.bind(evidence: evidence, expected: store.snapshot(),
                confirmLegacyOwnership: true, confirmMemories: false, backup: { _, _ in }, validateCurrent: {}))
            XCTAssertEqual(preferences.writes, [])
        }
    }

    func testPresetStoreRejectsWrongTypeExternalOverwriteAndLostWrite() throws {
        let wrong = ProfilePreferences(["picture_presets_v1": "wrong-type"])
        let wrongStore = PresetStore(defaults: wrong)
        XCTAssertNotNil(wrongStore.loadError); XCTAssertThrowsError(try wrongStore.save(.init()))
        XCTAssertEqual(wrong.writes, [])
        let changed = ProfilePreferences(["picture_presets_v1": legacy])
        let changedStore = PresetStore(defaults: changed)
        changed.values["picture_presets_v1"] = Data("{}".utf8)
        XCTAssertThrowsError(try changedStore.save(.init()))
        XCTAssertEqual(changed.data(forKey: "picture_presets_v1"), Data("{}".utf8))
        let lost = ProfilePreferences(["picture_presets_v1": legacy])
        let lostStore = PresetStore(defaults: lost)
        lost.write = { _, _ in false }
        XCTAssertThrowsError(try lostStore.save(.init()))
        XCTAssertEqual(lostStore.configuration.baseline?.deviceIdentity, "192.0.2.7")
        XCTAssertEqual(lost.data(forKey: "picture_presets_v1"), legacy)
    }
}
