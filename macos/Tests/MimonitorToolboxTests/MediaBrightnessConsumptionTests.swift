import AppKit
import XCTest
import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor
final class MediaBrightnessConsumptionTests: XCTestCase {
    private func makeState(_ runtime: PreviewRuntime, focusedDisplay: CGDirectDisplayID = 1) -> AppCoordinator {
        runtime.preferences.set(true, forKey: "media_brightness_keys_enabled")
        runtime.preferences.set(false, forKey: "media_brightness_native_osd")
        runtime.preferences.set(5, forKey: "media_brightness_step")
        let base = runtime.environment(mode: .live)
        var system = base.system
        system.isTrusted = { true }
        system.targetDisplay = { _ in 1 }
        system.focusedDisplay = { focusedDisplay }
        // Run the production callback wiring with only in-memory dependencies.
        let state = AppCoordinator(environment: AppEnvironment(mode: .live,
            preferences: base.preferences, adb: base.adb, hotkeys: base.hotkeys,
            feedback: base.feedback, scheduler: base.scheduler, system: system,
            now: base.now, calendar: base.calendar, presetDevice: base.presetDevice))
        state.start()
        state.adb.ip = runtime.display.identity
        state.connectionStatus = .connected("Fake monitor")
        state.currentValues["picture_backlight"] = "50"
        return state
    }

    private func keyDown(_ keyCode: CGKeyCode) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
        event.flags = []
        return event
    }

    private func systemDefined(_ keyType: Int32) throws -> CGEvent {
        try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: (Int(keyType) << 16) | 0x0A00, data2: 0)?.cgEvent)
    }

    func testKeyDownBrightnessIsConsumedOnlyWhileConnected() async throws {
        let runtime = PreviewRuntime()
        let state = makeState(runtime)
        defer { state.stop() }
        let handle = try XCTUnwrap(runtime.hotkeyDriver.handler)

        XCTAssertTrue(state.shouldHandleMediaBrightnessForFocus())
        XCTAssertTrue(handle(.keyDown, try keyDown(144)))
        XCTAssertEqual(state.mediaBrightnessPreview, 55)
        XCTAssertEqual(state.currentValues["picture_backlight"], "55")
        XCTAssertEqual(runtime.feedback.hints, ["背光:55"])
        await state.waitForPendingWork()

        state.connectionStatus = .disconnected
        XCTAssertTrue(state.shouldHandleMediaBrightnessForFocus())
        XCTAssertFalse(handle(.keyDown, try keyDown(145)))
        XCTAssertEqual(state.mediaBrightnessPreview, 55)
        XCTAssertEqual(state.currentValues["picture_backlight"], "55")
        XCTAssertEqual(runtime.feedback.hints, ["背光:55"])
        XCTAssertEqual(runtime.hotkeyDriver.starts, 1)
    }

    func testSystemDefinedBrightnessIsConsumedOnlyWhileConnected() async throws {
        let runtime = PreviewRuntime()
        let state = makeState(runtime)
        defer { state.stop() }
        let handle = try XCTUnwrap(runtime.hotkeyDriver.handler)
        let down = try systemDefined(HotkeyManager.keyTypeBrightnessDown)

        XCTAssertTrue(state.shouldHandleMediaBrightnessForFocus())
        XCTAssertTrue(handle(down.type, down))
        XCTAssertEqual(state.mediaBrightnessPreview, 45)
        XCTAssertEqual(state.currentValues["picture_backlight"], "45")
        XCTAssertEqual(runtime.feedback.hints, ["背光:45"])
        await state.waitForPendingWork()

        state.connectionStatus = .disconnected
        let up = try systemDefined(HotkeyManager.keyTypeBrightnessUp)
        XCTAssertTrue(state.shouldHandleMediaBrightnessForFocus())
        XCTAssertFalse(handle(up.type, up))
        XCTAssertEqual(state.mediaBrightnessPreview, 45)
        XCTAssertEqual(state.currentValues["picture_backlight"], "45")
        XCTAssertEqual(runtime.feedback.hints, ["背光:45"])
        XCTAssertEqual(runtime.hotkeyDriver.starts, 1)
    }

    func testConnectedBrightnessOutsideTargetDisplayPassesThrough() async throws {
        let runtime = PreviewRuntime()
        let state = makeState(runtime, focusedDisplay: 2)
        defer { state.stop() }
        let handle = try XCTUnwrap(runtime.hotkeyDriver.handler)
        let event = try systemDefined(HotkeyManager.keyTypeBrightnessDown)

        XCTAssertTrue(state.isConnected)
        XCTAssertFalse(state.shouldHandleMediaBrightnessForFocus())
        XCTAssertFalse(handle(.keyDown, try keyDown(144)))
        XCTAssertFalse(handle(event.type, event))
        XCTAssertNil(state.mediaBrightnessPreview)
        XCTAssertEqual(state.currentValues["picture_backlight"], "50")
        XCTAssertTrue(runtime.feedback.hints.isEmpty)
        await state.waitForPendingWork()
    }
}
