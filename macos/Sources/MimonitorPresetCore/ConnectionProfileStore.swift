import CryptoKit
import CoreFoundation
import Foundation
import ToolboxDomain

/// Called only under PresetWorker's single lock. PreferencesStore provides no durable
/// transaction: this owner checks the storage view, and startup must revalidate identity.
final class ConnectionProfileStore {
    static let key = "connection_profile_v1"
    private static let keys = ["saved_ip", "picture_presets_v1", key]
    private let preferences: any PreferencesStore
    private var failure: String?
    private var warning: String?

    init(preferences: any PreferencesStore) { self.preferences = preferences }

    func snapshot() -> ConnectionProfileSnapshot {
        do {
            let raw = try capture()
            let keys = try ownership(raw)
            let profile = try decodeProfile(raw[Self.key]!)
            return .init(profile: profile, error: failure, warning: warning,
                         ownershipKeys: keys, token: try digest(raw))
        } catch {
            return .init(profile: nil, error: error.localizedDescription, warning: warning,
                         ownershipKeys: [], token: (try? digest(capture())) ?? "")
        }
    }

    func savePreference(endpoint: AdbEndpoint, expected: ConnectionProfileSnapshot,
                        backup: (Data, String) throws -> Void,
                        validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        let current = try checked(expected)
        let reference = ConnectionEndpointReference(endpoint: endpoint)
        guard reference.isValid else { throw PresetError("连接端点无效，配置未写入") }
        var profile = current.profile ?? emptyProfile(reference)
        profile.preference = endpoint.isUSB ? .usb : .tcp
        profile.selectedEndpoint = reference
        if profile == current.profile { try validateCurrent(); return current }
        return try commit(profile, expected: current, mirror: endpoint,
                          backup: backup, validateCurrent: validateCurrent)
    }

    func bind(evidence: IdentityEvidence, expected: ConnectionProfileSnapshot,
              confirmLegacyOwnership: Bool, confirmMemories: Bool,
              backup: (Data, String) throws -> Void,
              validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        let current = try checked(expected)
        guard evidence.policyVersion == 1,
              DeviceIdentityParser.stableIdentifier(roSerialno: evidence.roSerialno, roBootSerialno: evidence.roBootSerialno) == evidence.stableIdentifier else {
            throw PresetError("物理身份缺少可靠属性证据")
        }
        guard current.ownershipKeys.count <= 1 else { throw PresetError("旧配置包含多个所有者，必须先审查，不能自动合并") }
        let reference = ConnectionEndpointReference(endpoint: evidence.endpoint)
        var profile = current.profile ?? emptyProfile(reference)
        guard !profile.devices.contains(where: { $0.endpoints.contains(reference) && $0.stableIdentifier != evidence.stableIdentifier }) else {
            throw PresetError("所选端点的物理身份与已有登记冲突")
        }
        let index = profile.devices.firstIndex { $0.stableIdentifier == evidence.stableIdentifier }
        let existing = index.map { profile.devices[$0] }
        if reference.isUSB, let existing,
           existing.endpoints.contains(where: { $0.isUSB && $0 != reference }) {
            throw PresetError("两个不同 USB 端点声称同一物理身份，不能自动合并")
        }
        var deviceID = existing?.deviceID ?? UUID()
        let key: String
        if let owner = current.ownershipKeys.first {
            if let existing {
                guard existing.presetIdentityKey == owner else { throw PresetError("旧配置所有权与登记不一致") }
                key = existing.presetIdentityKey
            } else {
                guard confirmLegacyOwnership else { throw PresetError("必须明确确认旧基线和未完成任务属于当前设备") }
                if owner.hasPrefix("device:") {
                    let suffix = String(owner.dropFirst("device:".count))
                    guard let sessionBoundID = UUID(uuidString: suffix), suffix == sessionBoundID.uuidString.lowercased(),
                          !profile.devices.contains(where: { $0.deviceID == sessionBoundID }) else {
                        throw PresetError("未登记的设备命名空间无效或已有所有者")
                    }
                    // A prior session-only user binding may have created this baseline.
                    // Upgrade only after the same explicit legacy ownership confirmation.
                    deviceID = sessionBoundID
                }
                key = owner
            }
        } else { key = existing?.presetIdentityKey ?? "device:\(deviceID.uuidString.lowercased())" }
        guard !profile.devices.contains(where: { $0.deviceID != deviceID && ($0.presetIdentityKey == key || $0.legacyAliases.contains(key)) }) else {
            throw PresetError("旧身份别名已属于另一设备")
        }
        let aliases = key.hasPrefix("device:") ? [] : [key]
        var endpoints = existing?.endpoints ?? []
        if !endpoints.contains(reference) { endpoints.append(reference) }
        let nextMemoryOwner = confirmMemories ? deviceID : profile.memoryOwnerDeviceID
        // Repeated confirmation uses the same device/key/revision and does not refresh timestamps.
        if let existing, existing.endpoints == endpoints, existing.legacyAliases == aliases,
           profile.selectedEndpoint == reference, profile.memoryOwnerDeviceID == nextMemoryOwner {
            try validateCurrent(); return current
        }
        let record = ConnectionDeviceRecord(deviceID: deviceID, stableIdentifier: evidence.stableIdentifier,
            presetIdentityKey: key, legacyAliases: aliases, endpoints: endpoints,
            bindingRevision: (existing?.bindingRevision ?? 0) + 1,
            bindingSource: .verifiedPropertiesWithUserConfirmation, evidence: .init(evidence))
        if let index { profile.devices[index] = record } else { profile.devices.append(record) }
        profile.selectedEndpoint = reference; profile.preference = evidence.endpoint.isUSB ? .usb : .tcp
        profile.memoryOwnerDeviceID = nextMemoryOwner
        return try commit(profile, expected: current, mirror: evidence.endpoint,
                          backup: backup, validateCurrent: validateCurrent)
    }

    /// Restore only the newly introduced key. Old preset bytes and saved_ip are never restored.
    func restore(backupData: Data, expected: ConnectionProfileSnapshot,
                 backup: (Data, String) throws -> Void,
                 validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        // Explicit rollback may recover a malformed/newer envelope. It still requires an
        // exact current raw snapshot and a backup, never a guessed/default replacement.
        try checkedRawToken(expected)
        let package = try PropertyListSerialization.propertyList(from: backupData, format: nil)
        guard let object = package as? [String: Any], object["schemaVersion"] as? Int == 1,
              object["migrationVersion"] as? Int == 1, object["bindingVersion"] as? Int == 1,
              let originalData = object["rawSnapshotJSON"] as? Data,
              let originalDigest = object["originalDigest"] as? String,
              Self.sha(originalData) == originalDigest else { throw PresetError("连接配置备份校验失败") }
        let original = try JSONDecoder().decode([String: RawPreference].self, from: originalData)
        guard Set(original.keys) == Set(Self.keys), let value = original[Self.key] else { throw PresetError("连接配置备份缺少原始键") }
        try validateCurrent()
        let before = try capture()
        let currentBackup = try makeBackup(before)
        try backup(currentBackup, Self.sha(currentBackup))
        try checkedRawToken(expected); try validateCurrent()
        value.restore(to: preferences, key: Self.key)
        guard try capture()[Self.key] == value else { failure = "连接配置回滚回读失败，已停止身份绑定"; throw PresetError(failure!) }
        failure = nil; warning = nil
        return snapshot()
    }

    private func commit(_ proposed: ConnectionProfile, expected: ConnectionProfileSnapshot, mirror: AdbEndpoint,
                        backup: (Data, String) throws -> Void,
                        validateCurrent: () throws -> Void) throws -> ConnectionProfileSnapshot {
        try validateCurrent()
        _ = try checked(expected)
        let original = try capture()
        let data = try makeBackup(original)
        let identifier = Self.sha(data)
        try backup(data, identifier)
        // A backup callback may block or reenter an external writer. Recheck all original bytes.
        _ = try checked(expected); try validateCurrent()
        var profile = proposed
        profile.revision = (expected.profile?.revision ?? 0) + 1
        profile.migration = .init(migrationVersion: 1, originalDigest: try digest(original), backupIdentifier: identifier)
        try validate(profile)
        let encoded = try Self.encode(profile)
        preferences.set(encoded, forKey: Self.key)
        do {
            guard let readback = preferences.object(forKey: Self.key) as? Data, readback == encoded,
                  try decodeProfile(.data(readback)) == profile else { throw PresetError("连接配置写入回读不一致") }
            // No competing edit to legacy ownership may be accepted during the write itself.
            let after = try capture()
            guard after["picture_presets_v1"] == original["picture_presets_v1"],
                  after["saved_ip"] == original["saved_ip"] else { throw PresetError("提交时原配置发生并发修改") }
            try validateCurrent()
        } catch {
            // Restore only a value still owned by this attempt; never clobber another writer.
            if preferences.object(forKey: Self.key) as? Data == encoded { original[Self.key]!.restore(to: preferences, key: Self.key) }
            failure = "连接配置提交失败，已停用新绑定：\(error.localizedDescription)"
            throw PresetError(failure!)
        }
        warning = nil
        if !mirror.isUSB, mirror.tcpPort == 5555 {
            preferences.set(mirror.tcpHost, forKey: "saved_ip")
            if preferences.object(forKey: "saved_ip") as? String != mirror.tcpHost {
                warning = "连接配置已保存，但旧 saved_ip 镜像回读失败；仍以新配置为准"
            }
        }
        return snapshot()
    }

    private func checked(_ expected: ConnectionProfileSnapshot) throws -> ConnectionProfileSnapshot {
        let current = snapshot()
        if let error = current.error { throw PresetError(error) }
        guard !expected.token.isEmpty, current.token == expected.token else { throw PresetError("原配置已改变，请重新审查后确认") }
        return current
    }
    private func checkedRawToken(_ expected: ConnectionProfileSnapshot) throws {
        guard !expected.token.isEmpty, try digest(capture()) == expected.token else {
            throw PresetError("原配置已改变，请重新审查后确认")
        }
    }
    private func emptyProfile(_ endpoint: ConnectionEndpointReference) -> ConnectionProfile {
        .init(revision: 0, preference: endpoint.isUSB ? .usb : .tcp, selectedEndpoint: endpoint,
              devices: [], memoryOwnerDeviceID: nil,
              migration: .init(migrationVersion: 1, originalDigest: "", backupIdentifier: ""))
    }
    private func ownership(_ raw: [String: RawPreference]) throws -> [String] {
        guard case .data(let data) = raw["picture_presets_v1"] else {
            if raw["picture_presets_v1"] == .absent { return [] }
            throw PresetError("预设配置类型错误，已保留原值")
        }
        let configuration: PresetConfiguration
        do { configuration = try JSONDecoder().decode(PresetConfiguration.self, from: data) }
        catch { throw PresetError("预设配置无法读取，已保留原数据：\(error.localizedDescription)") }
        let keys = [configuration.baseline?.deviceIdentity, configuration.activeDeviceIdentity,
                    configuration.session?.deviceIdentity].compactMap { $0 }
        guard !keys.contains(where: { $0.isEmpty }) else { throw PresetError("旧预设所有权字段为空，不能自动绑定") }
        return Array(Set(keys)).sorted()
    }
    private func decodeProfile(_ raw: RawPreference) throws -> ConnectionProfile? {
        if raw == .absent { return nil }
        guard case .data(let data) = raw else { throw PresetError("连接配置类型错误，已保留原值") }
        do {
            let profile = try JSONDecoder().decode(ConnectionProfile.self, from: data)
            try validate(profile); return profile
        } catch { throw PresetError("连接配置无法读取，已保留原数据：\(error.localizedDescription)") }
    }
    private func validate(_ profile: ConnectionProfile) throws {
        func validDigest(_ value: String) -> Bool { value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        guard profile.schemaVersion == 1, profile.revision > 0, profile.revision < Int.max,
              let selected = profile.selectedEndpoint, selected.isValid,
              (profile.preference == .usb) == selected.isUSB,
              profile.migration.migrationVersion == 1,
              validDigest(profile.migration.originalDigest), validDigest(profile.migration.backupIdentifier) else {
            throw PresetError("连接配置 schema、版本或迁移记录不完整")
        }
        var ids = Set<UUID>(), identifiers = Set<String>(), aliases = Set<String>(), endpoints: [ConnectionEndpointReference] = []
        for record in profile.devices {
            guard ids.insert(record.deviceID).inserted, !record.stableIdentifier.isEmpty,
                  identifiers.insert(record.stableIdentifier).inserted, !record.presetIdentityKey.isEmpty,
                  aliases.insert(record.presetIdentityKey).inserted, record.bindingRevision > 0, record.bindingRevision < Int.max,
                  !record.endpoints.isEmpty, record.endpoints.allSatisfy(\.isValid),
                  record.endpoints.filter(\.isUSB).count <= 1,
                  record.evidence.policyVersion == 1, record.endpoints.contains(record.evidence.endpoint),
                  DeviceIdentityParser.stableIdentifier(roSerialno: record.evidence.roSerialno, roBootSerialno: record.evidence.roBootSerialno) == record.stableIdentifier else {
                throw PresetError("连接配置设备登记重复或证据不完整")
            }
            if record.presetIdentityKey.hasPrefix("device:") {
                guard record.presetIdentityKey == "device:\(record.deviceID.uuidString.lowercased())", record.legacyAliases.isEmpty else { throw PresetError("设备身份命名空间冲突") }
            } else {
                guard record.legacyAliases == [record.presetIdentityKey] else { throw PresetError("旧身份别名记录不完整") }
            }
            for endpoint in record.endpoints {
                guard !endpoints.contains(endpoint) else { throw PresetError("连接端点被重复登记") }
                endpoints.append(endpoint)
            }
        }
        if let owner = profile.memoryOwnerDeviceID, !ids.contains(owner) { throw PresetError("全局记忆所有者未登记") }
    }
    private func capture() throws -> [String: RawPreference] {
        try Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, try RawPreference(preferences.object(forKey: $0))) })
    }
    private func digest(_ raw: [String: RawPreference]) throws -> String { Self.sha(try Self.encode(raw)) }
    private func makeBackup(_ raw: [String: RawPreference]) throws -> Data {
        let original = try Self.encode(raw)
        return try PropertyListSerialization.data(fromPropertyList: ["schemaVersion": 1, "migrationVersion": 1, "bindingVersion": 1,
            "originalDigest": Self.sha(original), "rawSnapshotJSON": original], format: .binary, options: 0)
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// A lossless, Sendable property-list value with explicit absence and number types.
private indirect enum RawPreference: Codable, Equatable, Sendable {
    case absent, string(String), data(Data), boolean(Bool), integer(Int64), unsignedInteger(UInt64), real(Double), date(Date)
    case array([RawPreference]), dictionary([String: RawPreference])
    init(_ value: Any?) throws {
        guard let value else { self = .absent; return }
        if let value = value as? Data { self = .data(value) }
        else if let value = value as? String { self = .string(value) }
        else if let value = value as? Date { self = .date(value) }
        else if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .boolean(value.boolValue) }
            else if String(cString: value.objCType).contains(where: { "fd".contains($0) }) {
                guard value.doubleValue.isFinite else { throw PresetError("偏好包含不可备份数值，已保留原值") }
                self = .real(value.doubleValue)
            } else if String(cString: value.objCType) == "Q" { self = .unsignedInteger(value.uint64Value) }
            else { self = .integer(value.int64Value) }
        } else if let value = value as? [Any] { self = .array(try value.map(Self.init)) }
        else if let value = value as? [String: Any] { self = .dictionary(try value.mapValues(Self.init)) }
        else { throw PresetError("偏好包含无法无损备份的类型，已保留原值") }
    }
    private var object: Any? {
        switch self {
        case .absent: return nil
        case .string(let value): return value
        case .data(let value): return value
        case .boolean(let value): return value
        case .integer(let value): return value
        case .unsignedInteger(let value): return value
        case .real(let value): return value
        case .date(let value): return value
        case .array(let value): return value.map { $0.object! }
        case .dictionary(let value): return value.mapValues { $0.object! }
        }
    }
    func restore(to preferences: any PreferencesStore, key: String) {
        if case .absent = self { preferences.removeObject(forKey: key) }
        else { preferences.set(object, forKey: key) }
    }
}
