import ToolboxDomain
import ToolboxApplication
import Foundation
import Observation
import XCTest
import MimonitorPresetCore
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

private final class ObservationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
final class ObservationTests: XCTestCase {
    func testSettingsConstructionLoadsExistingKeysWithoutApplyingTheme() {
        let preferences = MemoryPreferences()
        preferences.set("light", forKey: "theme")
        preferences.set("exit", forKey: "close_behavior")
        var themes: [String] = []
        let model = SettingsModel(preferences: preferences, applyTheme: { themes.append($0) })
        XCTAssertEqual(model.theme, "light")
        XCTAssertEqual(model.closeBehavior, "exit")
        XCTAssertTrue(themes.isEmpty)
        model.theme = "dark"; model.closeBehavior = "tray"
        XCTAssertEqual(themes, ["dark"])
        XCTAssertEqual(preferences.string(forKey: "theme"), "dark")
        XCTAssertEqual(preferences.string(forKey: "close_behavior"), "tray")
    }

    func testLogCapRetainsSequenceForAutoScroll() {
        let model = LogModel()
        for i in 0..<510 { model.append("line \(i)") }
        XCTAssertEqual(model.lines.count, 500)
        XCTAssertEqual(model.lines.first, "line 10")
        XCTAssertEqual(model.sequence, 510)
        let changes = ObservationCount()
        withObservationTracking { _ = model.sequence } onChange: { changes.increment() }
        model.append("next")
        XCTAssertEqual(model.lines.count, 500)
        XCTAssertEqual(model.sequence, 511)
        XCTAssertEqual(changes.value, 1)
    }

    func testVolumeDoesNotInvalidatePictureOrPresetReaders() {
        let state = PreviewRuntime().makeState()
        let picture = ObservationCount(), presets = ObservationCount(), volume = ObservationCount()
        withObservationTracking { _ = state.currentValues["picture_backlight"] } onChange: { picture.increment() }
        withObservationTracking { _ = state.presetConfiguration } onChange: { presets.increment() }
        withObservationTracking { _ = state.dashboardVolume } onChange: { volume.increment() }
        state.seedSimulationReadings(volume: 25, muted: false)
        XCTAssertEqual(picture.value, 0)
        XCTAssertEqual(presets.value, 0)
        XCTAssertEqual(volume.value, 1)
    }

    func testConnectionRecoveryIntentIsObservedWithoutGlobalNotifications() {
        let state = PreviewRuntime().makeState(), changes = ObservationCount()
        withObservationTracking { _ = state.connectionIntent.allowsAutomaticRecovery } onChange: { changes.increment() }
        state.logs.append("unrelated")
        XCTAssertEqual(changes.value, 0)
        state.disconnectAdb()
        XCTAssertEqual(changes.value, 1)
    }

    func testKeyboardActionFacadePreservesPreferenceKeys() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.mediaVolumeStep = 7; state.mediaBrightnessStep = 9
        state.mediaVolumeOutputName = "Mi Monitor (eqMac)"
        state.hotkeyCountdownSeconds = 1.1
        XCTAssertEqual(state.keyboard.mediaVolumeStep, 7)
        XCTAssertEqual(runtime.preferences.integer(forKey: "media_volume_step"), 7)
        XCTAssertEqual(runtime.preferences.integer(forKey: "media_brightness_step"), 9)
        XCTAssertEqual(runtime.preferences.string(forKey: "media_volume_output_name"), "Mi Monitor (eqMac)")
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
    }

    func testDisconnectInvalidatesPresetIdentityReadersWithoutChangingConfiguration() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        var config = PresetConfiguration()
        config.activeDeviceIdentity = runtime.display.identity
        config.activePresetID = "work"
        state.presetConfiguration = config
        let changes = ObservationCount()
        withObservationTracking { _ = state.activePresetID } onChange: { changes.increment() }
        XCTAssertEqual(state.activePresetID, "work")
        state.disconnectAdb()
        XCTAssertEqual(changes.value, 1)
        XCTAssertNil(state.activePresetID)
        XCTAssertEqual(state.presetConfiguration, config)
    }
}
