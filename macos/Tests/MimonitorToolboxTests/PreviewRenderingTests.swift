import AppKit
import SwiftUI
import XCTest
import ToolboxApplication
import ToolboxDomain
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class PreviewRenderingTests: XCTestCase {
    func testIntegratedSettingsPanesShareTheSessionWithoutQueryingTheDisplay() async {
        let _ = NSApplication.shared
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let session = ToolboxSession(coordinator: state)
        defer { state.stop() }
        let originalSession = state.adb.session().sessionID
        let originalCommands = runtime.display.recordedCommands
        XCTAssertFalse(state.needsConnection(.settings))
        for pane in ToolboxSettingsPane.allCases {
            session.settingsPane = pane
            session.showSettings()
            XCTAssertEqual(state.requestedPage, .settings)
            let originalEffects = runtime.effects
            let host = NSHostingView(rootView: ToolboxWindowContent(session: session))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            window.makeKeyAndOrderFront(nil)
            host.layoutSubtreeIfNeeded()
            await state.waitForPendingWork()
            XCTAssertGreaterThan(host.fittingSize.width, 0, pane.rawValue)
            XCTAssertNil(state.requestedPage)
            XCTAssertEqual(session.settingsPane, pane)
            XCTAssertEqual(state.adb.session().sessionID, originalSession)
            XCTAssertEqual(runtime.display.recordedCommands, originalCommands, pane.rawValue)
            XCTAssertEqual(runtime.effects, originalEffects, pane.rawValue)
            XCTAssertEqual(runtime.hotkeyDriver.starts, 0)
        }
    }

    func testNativeCandidateListOnlyEditsTheConnectionDraft() async throws {
        let _ = NSApplication.shared
        let runtime = PreviewRuntime(), state = runtime.makeState()
        defer { state.stop() }
        state.connection.scannedDevices = ["198.51.100.42", "203.0.113.7"]
        let session = state.adb.session(), commands = runtime.display.recordedCommands
        let originalHost = state.connection.ipInput
        let content = ConnectionSettingsSheet(connection: state.connection)
            .environment(\.toolboxActions, state).environment(state.connection).environment(state.logs)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
        }
        let table = try XCTUnwrap(descendants(host, of: NSTableView.self).first)
        XCTAssertEqual(table.numberOfRows, 2)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        let input = try XCTUnwrap(descendants(host, of: NSTextField.self).first {
            $0.placeholderString == "显示器地址"
        })
        XCTAssertEqual(input.stringValue, "203.0.113.7")
        XCTAssertEqual(state.connection.ipInput, originalHost)
        XCTAssertEqual(state.adb.session().sessionID, session.sessionID)
        XCTAssertEqual(runtime.display.recordedCommands, commands)
    }

    func testNativeDisplaySegmentsKeepDomainValuesUnknownAndDisabledStates() throws {
        let _ = NSApplication.shared
        let modes = [14, 9, 10].map { Option(label: RegisterMap.modeNames[$0] ?? "", value: $0) }
        for options in [modes, OptionLists.source] {
            var value = options[0].value
            var enabled = true
            var commits: [Int] = []
            func content() -> some View {
                SegmentedOptionPicker(options: options, selectedValue: value, controlSize: .regular) {
                    value = $0; commits.append($0)
                }.disabled(!enabled)
            }
            func segmented(in view: NSView) -> NSSegmentedControl? {
                if let control = view as? NSSegmentedControl { return control }
                return view.subviews.lazy.compactMap { segmented(in: $0) }.first
            }
            let host = NSHostingView(rootView: content())
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 40)
            host.layoutSubtreeIfNeeded()
            let control = try XCTUnwrap(segmented(in: host))
            XCTAssertEqual(control.selectedSegment, 0)
            control.selectedSegment = 1
            control.sendAction(control.action!, to: control.target)
            XCTAssertEqual(commits, [options[1].value])
            value = -1; host.rootView = content(); host.layoutSubtreeIfNeeded()
            XCTAssertEqual(control.selectedSegment, -1)
            XCTAssertEqual(commits.count, 1)
            value = options.last!.value; host.rootView = content(); host.layoutSubtreeIfNeeded()
            XCTAssertEqual(control.selectedSegment, options.count - 1)
            XCTAssertEqual(commits.count, 1)
            enabled = false; host.rootView = content(); host.layoutSubtreeIfNeeded()
            XCTAssertFalse(control.isEnabled)
            control.selectedSegment = 0
            control.sendAction(control.action!, to: control.target)
            XCTAssertEqual(commits.count, 1)
            XCTAssertEqual(value, options.last!.value)
        }
    }

    func testNativeSliderDragKeepsDraftSteppedAndCommitsOnlyOnRelease() throws {
        let _ = NSApplication.shared
        var value = 45.0
        var commits: [Double] = []
        var drafts: [(value: Double, commits: Int)] = []
        let host = NSHostingView(rootView: FastSlider(value: Binding(get: { value }, set: {
            value = $0
            drafts.append(($0, commits.count))
        }), range: 0...100, step: 1, onCommit: { commits.append($0) }).padding(8))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        let start = host.convert(NSPoint(x: 8 + 384 * 0.45, y: host.bounds.midY), to: nil)
        let middle = host.convert(NSPoint(x: 8 + 384 * 0.6, y: host.bounds.midY), to: nil)
        let end = host.convert(NSPoint(x: 8 + 384 * 0.75, y: host.bounds.midY), to: nil)
        func mouse(_ type: NSEvent.EventType, _ location: NSPoint, _ offset: TimeInterval) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + offset, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }
        let down = try mouse(.leftMouseDown, start, 0)
        let drag1 = try mouse(.leftMouseDragged, middle, 0.01)
        let drag2 = try mouse(.leftMouseDragged, end, 0.02)
        let up = try mouse(.leftMouseUp, end, 0.03)
        // Feed the native control's tracking loop, including its release, inside this test window.
        for event in [drag1, drag2, up] { NSApp.postEvent(event, atStart: false) }
        window.sendEvent(down)
        // SwiftUI can handle tracking without a nested AppKit event loop.
        while let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                          until: Date(), inMode: .default, dequeue: true) {
            window.sendEvent(event)
        }
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(drafts.count, 0)
        XCTAssertTrue(drafts.allSatisfy { $0.value == $0.value.rounded() && $0.commits == 0 })
        XCTAssertGreaterThan(value, 60)
        XCTAssertLessThan(value, 90)
        XCTAssertEqual(commits, [value])
    }

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
            GeneralSettingsView().environment(\.toolboxActions, state).environment(state.settings)
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
