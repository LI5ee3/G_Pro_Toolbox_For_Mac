import Foundation
import Testing
import XCTest
@testable import MimonitorPresetCore

/// Only the physical monitor is replaced. Persistence and transitions are real.
private final class Monitor: PresetDevice {
    var identity = "192.168.1.20"
    var values = ["picture_mode": "14", "picture_backlight": "40"]
    var failure = false
    func capture() throws -> [String: String] { values }
    func apply(_ values: [String: String]) throws -> PresetApplyReport {
        if failure { return PresetApplyReport(applied: [], failed: ["背光: 写入失败"], skipped: []) }
        self.values = values
        return PresetApplyReport(applied: ["画面模式", "背光"], failed: [], skipped: [])
    }
}

@Test(arguments: [false, true])
private func legacyTaskFieldsDoNotBlockOrReplacePresets(applicationIncomplete: Bool) throws {
    let data = Data("""
        {
          "presets": [{"id":"reading","name":"阅读","values":{"picture_backlight":"25"}}],
          "baseline": {"deviceIdentity":"192.168.1.20","values":{"picture_backlight":"40"}},
          "activePresetID": "reading", "activeDeviceIdentity": "192.168.1.20",
          "applicationIncomplete": \(applicationIncomplete), "menuBarPresetIDs": ["reading"],
          "tasks": [{"id":"old","presetID":"reading","start":"00:00","end":"23:59","enabled":true}],
          "session": {"taskID":"old","deviceIdentity":"old-task-owner","previousPresetID":"reading"}
        }
        """.utf8)
    let preferences = MemoryPreferences(["picture_presets_v1": data])
    let store = PresetStore(defaults: preferences)
    let engine = PresetEngine(store: store)
    let original = engine.configuration
    #expect(store.loadError == nil)
    #expect(original.presets.map(\.id) == ["reading"])
    #expect(original.baseline?.values["picture_backlight"] == "40")
    #expect(original.activePresetID == "reading")
    #expect(original.activeDeviceIdentity == "192.168.1.20")
    #expect(original.applicationIncomplete == applicationIncomplete)
    #expect(original.menuBarPresetIDs == ["reading"])
    #expect(preferences.data(forKey: "picture_presets_v1") == data)

    try engine.rename(id: "reading", name: "办公")
    let saved = try #require(preferences.data(forKey: "picture_presets_v1"))
    let json = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
    #expect(json["tasks"] == nil)
    #expect(json["session"] == nil)
    var expected = original
    expected.presets[0].name = "办公"
    #expect(PresetStore(defaults: preferences).configuration == expected)

    let monitor = Monitor()
    try engine.apply(id: "reading", device: monitor)
    #expect(monitor.values["picture_backlight"] == "25")
    try engine.restore(device: monitor)
    #expect(monitor.values["picture_backlight"] == "40")
}

final class PresetEngineTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }
    private func store() -> PresetStore {
        let suite = "preset-test-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        return PresetStore(defaults: defaults)
    }

    func testSwitchingPresetsDoesNotOverwriteBaselineAndRestoreClearsActive() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let first = try engine.create(name: "日间", device: monitor)
        monitor.values["picture_backlight"] = "20"
        let second = try engine.create(name: "夜间", device: monitor)
        try engine.apply(id: first.id, device: monitor)
        try engine.apply(id: second.id, device: monitor)
        try engine.restore(device: monitor)
        XCTAssertEqual(monitor.values["picture_backlight"], "40")
        XCTAssertNil(engine.configuration.activePresetID)
    }

    func testCreateAndRenameAvoidDuplicateNamesAndPreservePresetIdentity() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let first = try engine.create(name: "阅读", device: monitor)
        let second = try engine.create(name: " 阅读 ", device: monitor)
        XCTAssertEqual(second.name, "阅读 (2)")
        try engine.rename(id: first.id, name: "办公")
        XCTAssertEqual(engine.configuration.presets.first?.id, first.id)
        XCTAssertEqual(engine.configuration.presets.first?.name, "办公")
    }

    func testAutosaveOnlyUpdatesThePresetCapturedByTheEdit() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let first = try engine.create(name: "一", device: monitor)
        let second = try engine.create(name: "二", device: monitor)
        monitor.values["picture_backlight"] = "80"
        try engine.synchronize(id: first.id, device: monitor)
        XCTAssertEqual(engine.configuration.presets.first?.values["picture_backlight"], "40")
        try engine.synchronize(id: second.id, device: monitor)
        XCTAssertEqual(engine.configuration.presets.last?.values["picture_backlight"], "80")
    }

    func testFailedApplyKeepsBaselineAndDoesNotMarkTargetActive() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let first = try engine.create(name: "一", device: monitor)
        try engine.restore(device: monitor)
        monitor.failure = true
        XCTAssertThrowsError(try engine.apply(id: first.id, device: monitor))
        XCTAssertNil(engine.configuration.activePresetID)
        XCTAssertEqual(engine.configuration.baseline?.values["picture_backlight"], "40")
    }

    func testCannotRestoreSnapshotToDifferentMonitor() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        _ = try engine.create(name: "一", device: monitor)
        monitor.identity = "192.168.1.30"
        monitor.values["picture_backlight"] = "99"
        XCTAssertThrowsError(try engine.restore(device: monitor))
        XCTAssertEqual(monitor.values["picture_backlight"], "99")
    }

    func testManualApplyRetryDoesNotReplaceBaselineWithPartialFailedValues() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let preset = try engine.create(name: "游戏", device: monitor)
        try engine.restore(device: monitor)
        monitor.values["picture_backlight"] = "60"
        monitor.failure = true
        XCTAssertThrowsError(try engine.apply(id: preset.id, device: monitor))
        // Some items reached hardware despite the failed batch.
        monitor.values["picture_backlight"] = "99"
        monitor.failure = false
        try engine.apply(id: preset.id, device: monitor)
        try engine.restore(device: monitor)
        XCTAssertEqual(monitor.values["picture_backlight"], "60")
    }

    func testFailedSwitchCannotAutosaveMixedValuesIntoOriginalPreset() throws {
        let engine = PresetEngine(store: store())
        let monitor = Monitor()
        let previous = try engine.create(name: "电影", device: monitor)
        monitor.values["picture_backlight"] = "70"
        let game = try engine.create(name: "游戏", device: monitor)
        try engine.apply(id: previous.id, device: monitor)
        monitor.failure = true
        XCTAssertThrowsError(try engine.apply(id: game.id, device: monitor))
        monitor.values["picture_backlight"] = "99"
        XCTAssertThrowsError(try engine.synchronize(id: previous.id, device: monitor))
        XCTAssertEqual(engine.configuration.presets.first?.values["picture_backlight"], "40")
    }

}
