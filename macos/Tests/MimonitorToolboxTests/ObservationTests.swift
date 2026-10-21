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

    func testUnrelatedLogWritesDoNotInvalidateSettingsReaders() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let changes = ObservationCount()
        withObservationTracking { _ = state.settings.theme } onChange: { changes.increment() }
        for i in 0..<500 { state.logs.append("\(i)") }
        XCTAssertEqual(changes.value, 0)
        state.settings.theme = "dark"
        XCTAssertEqual(changes.value, 1)
    }

    func testCloseBehaviorDoesNotInvalidateThemeReader() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let changes = ObservationCount()
        withObservationTracking { _ = state.settings.theme } onChange: { changes.increment() }
        state.settings.closeBehavior = "exit"
        XCTAssertEqual(changes.value, 0)
        state.settings.theme = "light"
        XCTAssertEqual(changes.value, 1)
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

    func testLegacyActionFacadeUsesSameLeafModelInstances() {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.theme = "dark"
        XCTAssertEqual(state.settings.theme, "dark")
        state.settings.closeBehavior = "exit"
        XCTAssertEqual(state.closeBehavior, "exit")
        state.logToFileEnabled = true
        XCTAssertTrue(state.logs.recordsToFile)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
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

    func testPictureMutationDoesNotInvalidateVolumeReader() {
        let state = PreviewRuntime().makeState(), changes = ObservationCount()
        withObservationTracking { _ = state.volume.dashboardVolume } onChange: { changes.increment() }
        state.currentValues["picture_backlight"] = "60"
        state.logs.append("picture changed")
        XCTAssertEqual(changes.value, 0)
        state.seedSimulationReadings(volume: 20, muted: false)
        XCTAssertEqual(changes.value, 1)
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

    func testBusyAndNavigationAreIndependentOfPresetConfiguration() {
        let state = PreviewRuntime().makeState(), changes = ObservationCount()
        withObservationTracking { _ = state.presets.presetConfiguration } onChange: { changes.increment() }
        state.isPresetBusy = true; state.requestedPage = .picture
        XCTAssertEqual(changes.value, 0)
        XCTAssertTrue(state.presets.isPresetBusy)
        XCTAssertEqual(state.navigation.requestedPage, .picture)
    }
}
