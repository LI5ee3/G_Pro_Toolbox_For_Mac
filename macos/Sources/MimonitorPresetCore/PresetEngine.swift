import Foundation

/// Synchronous state machine. The app runs it off-main on one serial device queue.
public final class PresetEngine {
    private let store: PresetStore
    public var configuration: PresetConfiguration { store.configuration }
    public var loadError: String? { store.loadError }
    public var onReport: ((PresetApplyReport) -> Void)?
    public init(store: PresetStore) { self.store = store }

    public func setMenuBarVisibility(id: String, visible: Bool) throws {
        try checkStorage()
        guard id == PicturePreset.baselineID || configuration.presets.contains(where: { $0.id == id }) else {
            throw PresetError("预设已被删除")
        }
        var config = configuration
        config.menuBarPresetIDs = config.normalizedMenuBarPresetIDs
        if visible {
            guard config.canEnableMenuBarPreset(id: id) else {
                throw PresetError("菜单栏最多添加 4 个预设，请先关闭一个已有预设的菜单栏显示")
            }
            if config.menuBarPresetIDs.contains(id) { return }
        }
        config.menuBarPresetIDs.removeAll { $0 == id }
        if visible { config.menuBarPresetIDs.append(id) }
        try store.save(config)
    }

    private func checkStorage() throws {
        if let loadError { throw PresetError(loadError) }
    }
    private func name(_ wanted: String, excluding id: String? = nil) throws -> String {
        let base = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw PresetError("请输入预设名称") }
        let taken = Set(configuration.presets.filter { $0.id != id }.map(\.name))
        var candidate = base; var suffix = 2
        while taken.contains(candidate) { candidate = "\(base) (\(suffix))"; suffix += 1 }
        return candidate
    }

    @discardableResult
    public func create(name wanted: String, device: PresetDevice) throws -> PicturePreset {
        try checkStorage()
        guard !configuration.applicationIncomplete else {
            throw PresetError("上次预设未完整应用，请先重新应用预设或返回无预设")
        }
        let finalName = try name(wanted)
        let values = try device.capture()
        guard !values.isEmpty else { throw PresetError("未读到画面设置，预设未创建") }
        var config = configuration
        if config.activePresetID == nil || config.activeDeviceIdentity != device.identity {
            config.baseline = PresetBaseline(deviceIdentity: device.identity, values: values)
        }
        let preset = PicturePreset(name: finalName, values: values)
        config.presets.append(preset)
        config.activePresetID = preset.id
        config.activeDeviceIdentity = device.identity
        try store.save(config)
        return preset
    }

    public func rename(id: String, name wanted: String) throws {
        var config = configuration
        guard let index = config.presets.firstIndex(where: { $0.id == id }) else { return }
        config.presets[index].name = try name(wanted, excluding: id)
        try store.save(config)
    }

    public func delete(id: String, device: PresetDevice?) throws {
        if configuration.activePresetID == id {
            guard let device else { throw PresetError("请连接显示器后再删除正在使用的预设") }
            try restore(device: device)
        }
        var config = configuration
        config.presets.removeAll { $0.id == id }
        config.menuBarPresetIDs.removeAll { $0 == id }
        try store.save(config)
    }

    public func apply(id: String, device: PresetDevice) throws {
        try switchTo(id: id, device: device, captureBaseline: true)
    }

    public func restore(device: PresetDevice) throws {
        try switchTo(id: PicturePreset.baselineID, device: device, captureBaseline: false)
    }

    private func switchTo(id: String, device: PresetDevice, captureBaseline: Bool) throws {
        try checkStorage()
        var config = configuration
        let values: [String: String]
        if id == PicturePreset.baselineID {
            guard let baseline = config.baseline, !baseline.values.isEmpty else {
                throw PresetError("还没有无预设的基线设置")
            }
            guard baseline.deviceIdentity == device.identity else {
                throw PresetError("无预设基线属于另一台显示器，不能还原到当前设备")
            }
            values = baseline.values
        } else {
            guard let preset = config.presets.first(where: { $0.id == id }) else {
                throw PresetError("预设已被删除")
            }
            values = preset.values
            let recoveringBaseline = config.applicationIncomplete && config.baseline?.deviceIdentity == device.identity
            if captureBaseline && !recoveringBaseline && (config.activePresetID == nil || config.activeDeviceIdentity != device.identity) {
                let baseline = try device.capture()
                guard !baseline.isEmpty else { throw PresetError("无法读取无预设基线，未应用预设") }
                config.baseline = PresetBaseline(deviceIdentity: device.identity, values: baseline)
                // Preserve the return point before any device write, even on partial failure.
                try store.save(config)
            }
        }
        config.applicationIncomplete = true
        try store.save(config)
        let result = try device.apply(values)
        onReport?(result)
        guard result.ok else { throw PresetError("预设未完整应用：\(result.summary)\n\(result.failed.joined(separator: "\n"))") }
        config.activePresetID = id == PicturePreset.baselineID ? nil : id
        config.activeDeviceIdentity = device.identity
        config.applicationIncomplete = false
        try store.save(config)
    }

    public func synchronize(id: String, device: PresetDevice) throws {
        guard configuration.activePresetID == id,
              configuration.activeDeviceIdentity == device.identity else { return }
        guard !configuration.applicationIncomplete else {
            throw PresetError("上次预设未完整应用，不会将混合参数保存到原预设，请先重新应用或返回无预设")
        }
        let values = try device.capture()
        guard !values.isEmpty else { throw PresetError("未读到画面设置，保留原预设") }
        var config = configuration
        guard let index = config.presets.firstIndex(where: { $0.id == id }) else { return }
        config.presets[index].values = values
        try store.save(config)
    }
}
