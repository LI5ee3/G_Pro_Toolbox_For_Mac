import Foundation

public struct PicturePreset: Codable, Equatable, Identifiable, Sendable {
    public static let baselineID = "__baseline__"
    public var id: String
    public var name: String
    public var values: [String: String]
    public init(id: String = UUID().uuidString, name: String, values: [String: String]) {
        self.id = id; self.name = name; self.values = values
    }
}

/// The ordinary, non-preset state.
public struct PresetBaseline: Codable, Equatable, Sendable {
    public var deviceIdentity: String
    public var values: [String: String]
}

public struct PresetConfiguration: Codable, Equatable, Sendable {
    public static let menuBarPresetLimit = 4
    public var normalizedMenuBarPresetIDs: [String] {
        let valid = Set(presets.map(\.id)).union([PicturePreset.baselineID])
        var seen = Set<String>()
        return Array(menuBarPresetIDs.filter { valid.contains($0) && seen.insert($0).inserted }
            .prefix(Self.menuBarPresetLimit))
    }
    public func canEnableMenuBarPreset(id: String) -> Bool {
        guard id == PicturePreset.baselineID || presets.contains(where: { $0.id == id }) else { return false }
        let enabled = normalizedMenuBarPresetIDs
        return enabled.contains(id) || enabled.count < Self.menuBarPresetLimit
    }
    public var menuBarPresetIDs: [String] = []
    public var menuBarPresets: [PicturePreset] {
        let enabled = Set(normalizedMenuBarPresetIDs)
        var result: [PicturePreset] = []
        if enabled.contains(PicturePreset.baselineID) {
            result.append(PicturePreset(id: PicturePreset.baselineID, name: "无预设", values: [:]))
        }
        result.append(contentsOf: presets.filter { enabled.contains($0.id) })
        return result
    }
    public var presets: [PicturePreset] = []
    public var baseline: PresetBaseline?
    public var activePresetID: String?
    public var activeDeviceIdentity: String?
    public var applicationIncomplete = false
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case presets, baseline, activePresetID, activeDeviceIdentity, applicationIncomplete, menuBarPresetIDs
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presets = try container.decodeIfPresent([PicturePreset].self, forKey: .presets) ?? []
        baseline = try container.decodeIfPresent(PresetBaseline.self, forKey: .baseline)
        activePresetID = try container.decodeIfPresent(String.self, forKey: .activePresetID)
        activeDeviceIdentity = try container.decodeIfPresent(String.self, forKey: .activeDeviceIdentity)
        applicationIncomplete = try container.decodeIfPresent(Bool.self, forKey: .applicationIncomplete) ?? false
        menuBarPresetIDs = try container.decodeIfPresent([String].self, forKey: .menuBarPresetIDs) ?? []
        menuBarPresetIDs = normalizedMenuBarPresetIDs
    }
}

public struct PresetApplyReport: Equatable, Sendable {
    public var applied: [String]
    public var failed: [String]
    public var skipped: [String]
    public var ok: Bool { failed.isEmpty && !applied.isEmpty }
    public init(applied: [String] = [], failed: [String] = [], skipped: [String] = []) {
        self.applied = applied; self.failed = failed; self.skipped = skipped
    }
    public var summary: String {
        "成功 \(applied.count) 项，跳过 \(skipped.count) 项，失败 \(failed.count) 项"
    }
}

public struct PresetError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public protocol PresetDevice {
    var identity: String { get }
    func capture() throws -> [String: String]
    func apply(_ values: [String: String]) throws -> PresetApplyReport
}

/// Accessed on the same serial queue as PresetEngine. Failed decode never overwrites saved data.
public final class PresetStore {
    public let defaults: any PreferencesStore
    public private(set) var configuration = PresetConfiguration()
    public private(set) var loadError: String?
    private let key = "picture_presets_v1"
    private var originalData: Data?
    public init(defaults: any PreferencesStore = UserDefaults.standard) {
        self.defaults = defaults
        if let value = defaults.object(forKey: key) {
            guard let data = value as? Data else {
                loadError = "预设配置类型错误，已保留原值"; return
            }
            originalData = data
            do { configuration = try JSONDecoder().decode(PresetConfiguration.self, from: data) }
            catch { loadError = "预设配置无法读取，已保留原数据：\(error.localizedDescription)" }
        }
    }
    func save(_ configuration: PresetConfiguration) throws {
        if let loadError { throw PresetError(loadError) }
        let current = defaults.object(forKey: key)
        guard (current == nil && originalData == nil) || (current as? Data == originalData && current is Data) else {
            loadError = "预设配置已被其他所有者修改，已保留当前值"
            throw PresetError(loadError!)
        }
        let data = try JSONEncoder().encode(configuration)
        defaults.set(data, forKey: key)
        guard defaults.object(forKey: key) as? Data == data else {
            loadError = "预设配置写入回读失败，已停止后续写入"
            throw PresetError(loadError!)
        }
        originalData = data
        self.configuration = configuration
    }
}
