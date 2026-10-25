import AppKit
import SwiftUI
import XCTest
import ToolboxApplication
import ToolboxDomain
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class PreviewRenderingTests: XCTestCase {
    func testFocusedSliderKeysCommitOnceClampAndIgnoreDisabledOrExternalUpdates() async throws {
        let _ = NSApplication.shared
        let runtime = PreviewRuntime(), state = runtime.makeState()
        defer { state.stop() }
        var commits: [Double] = []
        let focused = expectation(description: "Slider focused")
        func content(enabled: Bool) -> KeyboardSliderFixture {
            KeyboardSliderFixture(value: Binding(get: { state.keyboard.hotkeyCountdownSeconds }, set: { state.hotkeyCountdownSeconds = $0 }),
                                  enabled: enabled, onCommit: { commits.append($0) },
                                  onFocus: { focused.fulfill() })
        }
        let host = NSHostingView(rootView: content(enabled: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        await fulfillment(of: [focused], timeout: 2)
        func key(_ character: Int, _ code: UInt16) throws {
            let text = String(try XCTUnwrap(UnicodeScalar(character)))
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
            window.sendEvent(event)
            host.layoutSubtreeIfNeeded()
        }
        try key(NSRightArrowFunctionKey, 124)
        XCTAssertEqual(state.keyboard.hotkeyCountdownSeconds, 0.9, accuracy: 0.00001)
        XCTAssertEqual(commits.count, 1)
        try key(NSLeftArrowFunctionKey, 123)
        XCTAssertEqual(state.keyboard.hotkeyCountdownSeconds, 0.8, accuracy: 0.00001)
        XCTAssertEqual(commits.count, 2)
        state.hotkeyCountdownSeconds = 2.9; host.rootView = content(enabled: true); host.layoutSubtreeIfNeeded()
        XCTAssertEqual(commits.count, 2)
        try key(NSUpArrowFunctionKey, 126)
        try key(NSUpArrowFunctionKey, 126)
        XCTAssertEqual(state.keyboard.hotkeyCountdownSeconds, 3, accuracy: 0.00001)
        XCTAssertEqual(commits.count, 3)
        state.hotkeyCountdownSeconds = 0.2; host.rootView = content(enabled: true); host.layoutSubtreeIfNeeded()
        try key(NSDownArrowFunctionKey, 125)
        XCTAssertEqual(state.keyboard.hotkeyCountdownSeconds, 0.2)
        XCTAssertEqual(commits.count, 3)
        host.rootView = content(enabled: false); host.layoutSubtreeIfNeeded()
        try key(NSRightArrowFunctionKey, 124)
        XCTAssertEqual(state.keyboard.hotkeyCountdownSeconds, 0.2)
        XCTAssertEqual(commits.count, 3)
    }

    func testParameterPopupUsesDomainTagsAndExternalUpdatesDoNotWrite() async throws {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        var commits = 0
        func row(_ value: Int) -> ParameterPickerRow {
            ParameterPickerRow(title: "色域", options: OptionLists.gamut, selectedValue: value) {
                commits += 1
                state.setGamut($0)
            }
        }
        func popup(in view: NSView) -> NSPopUpButton? {
            if let popup = view as? NSPopUpButton { return popup }
            return view.subviews.lazy.compactMap { popup(in: $0) }.first
        }
        let host = NSHostingView(rootView: row(6))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 50)
        host.layoutSubtreeIfNeeded()
        let control = try XCTUnwrap(popup(in: host))
        XCTAssertEqual(control.titleOfSelectedItem, "DCI-P3")
        XCTAssertEqual(commits, 0)
        control.selectItem(withTag: 4) // AdobeRGB's domain value differs from its menu index.
        control.sendAction(control.action!, to: control.target)
        await state.waitForPendingWork()
        XCTAssertEqual(state.currentValues["tv_picture_advanced_video_color_space"], "4")
        XCTAssertEqual(commits, 1)
        let commands = runtime.display.recordedCommands
        host.rootView = row(5)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.titleOfSelectedItem, "BT2020")
        host.rootView = row(-1)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(control.titleOfSelectedItem, "未知")
        XCTAssertEqual(control.selectedItem?.tag, -1)
        control.sendAction(control.action!, to: control.target) // A readable placeholder cannot submit.
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(runtime.display.recordedCommands, commands)
        state.stop()
    }

    func testNativeAppPreferenceSegmentsKeepExistingStoredValues() throws {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        var controlsEnabled = true
        func content() -> some View {
            ToolsView().environment(\.toolboxActions, state).environment(state.connection)
                .environment(state.tools).environment(state.keyboard).environment(state.settings)
                .disabled(!controlsEnabled)
        }
        func segments(in view: NSView) -> [NSSegmentedControl] {
            (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { segments(in: $0) }
        }
        let host = NSHostingView(rootView: content())
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 800)
        host.layoutSubtreeIfNeeded()
        let controls = segments(in: host)
        let close = try XCTUnwrap(controls.first { $0.label(forSegment: 0) == "在菜单栏继续运行" })
        let theme = try XCTUnwrap(controls.first { $0.label(forSegment: 0) == "跟随系统" })
        close.selectedSegment = 1; close.sendAction(close.action!, to: close.target)
        theme.selectedSegment = 1; theme.sendAction(theme.action!, to: theme.target)
        XCTAssertEqual(state.settings.closeBehavior, "exit")
        XCTAssertEqual(state.settings.theme, "dark")
        XCTAssertEqual(runtime.preferences.string(forKey: "close_behavior"), "exit")
        XCTAssertEqual(runtime.preferences.string(forKey: "theme"), "dark")
        state.settings.closeBehavior = "tray"; state.settings.theme = "light"
        let effects = runtime.effects
        host.rootView = content(); host.layoutSubtreeIfNeeded()
        XCTAssertEqual(close.selectedSegment, 0)
        XCTAssertEqual(theme.selectedSegment, 2)
        XCTAssertEqual(runtime.preferences.string(forKey: "theme"), "light")
        XCTAssertEqual(runtime.effects, effects) // External selection updates must not reapply preferences.
        controlsEnabled = false
        host.rootView = content(); host.layoutSubtreeIfNeeded()
        XCTAssertFalse(close.isEnabled)
        XCTAssertFalse(theme.isEnabled)
        state.stop()
    }

    func testEnvironmentKeyPathCanBeSetBeforeAnActionConsumerExists() {
        let state = PreviewRuntime().makeState()
        var environment = EnvironmentValues()
        XCTAssertNil(environment.toolboxActions)
        environment[keyPath: \.toolboxActions] = state
        XCTAssertTrue(environment.toolboxActions === state)
    }

    func testEveryPageAndMenuPanelCanLayOutWithOnlyFakeDependencies() {
        for screen in ToolboxScreen.allCases {
            autoreleasepool {
                let runtime = PreviewRuntime(), state = runtime.makeState()
                let session = ToolboxSession(coordinator: state)
                let host = NSHostingView(rootView: ToolboxWindowContent(session: session, screen: screen))
                host.frame = NSRect(x: 0, y: 0, width: 1120, height: 900)
                host.layoutSubtreeIfNeeded()
                XCTAssertGreaterThan(host.fittingSize.width, 0, screen.rawValue)
                XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
                state.stop()
            }
        }
        let runtime = PreviewRuntime()
        let host = NSHostingView(rootView: ToolboxMenuBarContent(session: ToolboxSession(coordinator: runtime.makeState())))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 500)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
    }
}

private struct KeyboardSliderFixture: View {
    @Binding var value: Double
    let enabled: Bool
    let onCommit: (Double) -> Void
    let onFocus: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        FastSlider(value: $value, range: 0.2...3, step: 0.1, onCommit: onCommit)
            .disabled(!enabled).focused($focused)
            .onAppear { focused = true }
            .onChange(of: focused) { _, value in if value { onFocus() } }
            .padding(8)
    }
}
