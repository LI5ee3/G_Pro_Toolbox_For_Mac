import AppKit
import SwiftUI
import XCTest
import ToolboxApplication
import ToolboxDomain
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class PreviewRenderingTests: XCTestCase {
    func testSidebarSelectionUsesAvailableSystemSymbolVariants() {
        let expected: [(Page, String)] = [
            (.home, "house.fill"), (.picture, "paintpalette.fill"),
            (.presets, "square.stack.3d.up.fill"), (.game, "gamecontroller.fill"),
            (.source, "arrow.triangle.2.circlepath.circle.fill"), (.light, "lightbulb.fill"),
            (.menuBar, "menubar.rectangle"), (.tools, "wrench.and.screwdriver.fill"),
            (.settings, "gearshape.fill"), (.remote, "tv.fill")
        ]
        XCTAssertEqual(expected.count, Page.allCases.count)
        for (page, selectedName) in expected {
            let normal = SidebarNavigationLabel(title: page.title, page: page, selected: false).symbolName
            let selected = SidebarNavigationLabel(title: page.title, page: page, selected: true).symbolName
            XCTAssertEqual(normal, page.icon)
            XCTAssertEqual(selected, selectedName)
            XCTAssertNotNil(NSImage(systemSymbolName: normal, accessibilityDescription: nil))
            XCTAssertNotNil(NSImage(systemSymbolName: selected, accessibilityDescription: nil))
        }
    }

    func testSidebarSymbolTracksNativeRowEmphasisAndReuse() throws {
        let _ = NSApplication.shared
        let row = NSTableRowView()
        let image = SidebarSymbolImageView()
        row.addSubview(image)
        row.isEmphasized = true
        image.updateSymbol(page: .home, name: "house.fill", selected: true, animated: false)
        XCTAssertEqual(image.contentTintColor, .white)
        let home = try XCTUnwrap(image.image)
        row.isEmphasized = false
        XCTAssertEqual(image.contentTintColor, NSColor(Theme.actionAccent))
        row.isEmphasized = true
        XCTAssertEqual(image.contentTintColor, .white)
        XCTAssertTrue(image.image === home)
        image.updateSymbol(page: .home, name: "house.fill", selected: true, animated: true)
        XCTAssertTrue(image.image === home)
        image.updateSymbol(page: .settings, name: "gearshape", selected: false, animated: true)
        XCTAssertFalse(image.image === home)
        XCTAssertEqual(image.contentTintColor, NSColor(Theme.accent))
        image.removeFromSuperview()
        row.isEmphasized = false
        image.updateSymbol(page: .settings, name: "gearshape.fill", selected: true, animated: false)
        XCTAssertEqual(image.contentTintColor, NSColor(Theme.actionAccent))
        XCTAssertNotNil(image.image)
    }

    func testVideoInputSelectionKeepsNativeIndicators() {
        let _ = NSApplication.shared
        let host = NSHostingView(rootView: VideoInputPicker(selectedValue: 29, onSelect: { _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 740, height: 60)
        host.layoutSubtreeIfNeeded()
        func indicators(in view: NSView) -> [NSImageView] {
            if let image = view as? NSImageView { return [image] }
            return view.subviews.flatMap { indicators(in: $0) }
        }
        let initialViews = Set(indicators(in: host).map(ObjectIdentifier.init))
        XCTAssertEqual(initialViews.count, 4)
        for selection in [23, 24, 30, 29, -1] {
            host.rootView = VideoInputPicker(selectedValue: selection, onSelect: { _ in })
            host.layoutSubtreeIfNeeded()
            let current = indicators(in: host)
            XCTAssertEqual(Set(current.map(ObjectIdentifier.init)), initialViews)
            XCTAssertEqual(current.filter { $0.contentTintColor == .white }.count, selection == -1 ? 0 : 1)
        }
    }

    func testNativeSymbolImageReusesItsViewAcrossAnimatedAndImmediateUpdates() throws {
        let _ = NSApplication.shared
        let host = NSHostingView(rootView: ToolboxSymbolImage(name: VolumeSymbol.name(for: 33), animated: false))
        host.frame = NSRect(x: 0, y: 0, width: 24, height: 18)
        host.layoutSubtreeIfNeeded()
        func imageView(in view: NSView) -> NSImageView? {
            if let image = view as? NSImageView { return image }
            return view.subviews.lazy.compactMap { imageView(in: $0) }.first
        }
        let image = try XCTUnwrap(imageView(in: host))
        let low = try XCTUnwrap(image.image)
        host.rootView = ToolboxSymbolImage(name: VolumeSymbol.name(for: 34), animated: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(imageView(in: host) === image)
        let middle = try XCTUnwrap(image.image)
        XCTAssertFalse(middle === low)
        host.rootView = ToolboxSymbolImage(name: VolumeSymbol.name(for: 66), animated: true)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(image.image === middle)
        host.rootView = ToolboxSymbolImage(name: VolumeSymbol.name(for: 66, muted: true), animated: false)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(imageView(in: host) === image)
        XCTAssertNotNil(image.image)
        XCTAssertFalse(image.image === middle)
        host.rootView = ToolboxSymbolImage(name: "circle", animated: false)
        host.layoutSubtreeIfNeeded()
        let circle = try XCTUnwrap(image.image)
        host.rootView = ToolboxSymbolImage(name: "circle", animated: true, tint: .white)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(image.contentTintColor, .white)
        XCTAssertTrue(image.image === circle)
        host.rootView = ToolboxSymbolImage(name: "checkmark.circle.fill", animated: true, tint: .white)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(imageView(in: host) === image)
        XCTAssertNotNil(image.image)
        XCTAssertFalse(image.image === circle)
    }

    func testHUDUsesTheMenuBarIconWithoutTakingKeyboardFocus() async throws {
        let _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "HUD 测试")
        defer { HUDWindow.shared.stop(); NSStatusBar.system.removeStatusItem(item) }
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { item.button?.window?.isVisible == true }
        }, object: nil)
        await fulfillment(of: [shown], timeout: 2)
        let icon = try XCTUnwrap(item.button?.window)
        XCTAssertEqual(icon.level, .statusBar)
        let keyWindow = NSApp.keyWindow
        HUDWindow.shared.show(title: "音量", value: "16", countdown: 0.8)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.contentView is NSHostingView<HUDView> })
        let area = try XCTUnwrap(icon.screen).visibleFrame
        XCTAssertEqual(panel.frame.origin, HUDWindow.origin(anchor: icon.frame, in: area))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        XCTAssertEqual(panel.frame.size, HUDWindow.size)
        let host = try XCTUnwrap(panel.contentView as? NSHostingView<HUDView>)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.rootView.model.isPresented)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(host.rootView.model.showsCountdown)
        HUDWindow.shared.endCountdown()
        XCTAssertFalse(host.rootView.model.showsCountdown)
        HUDWindow.shared.show(title: "静音", value: "开")
        XCTAssertEqual(host.rootView.model.symbolName, "speaker.slash.fill")
        HUDWindow.shared.show(title: "静音", value: "关")
        XCTAssertEqual(host.rootView.model.symbolName, "speaker.wave.3.fill")
        HUDWindow.shared.show(title: "背光", value: "80")
        XCTAssertEqual(host.rootView.model.value, "80")
        let token = HUDWindow.shared.beginOperation(title: "切换预设")
        HUDWindow.shared.finishOperation(token: token, result: .success)
        XCTAssertEqual(NSApp.windows.filter { $0.contentView is NSHostingView<HUDView> }.count, 1)
        XCTAssertEqual(panel.frame.origin, HUDWindow.origin(anchor: icon.frame, in: area))
        HUDWindow.shared.stop()
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(host.rootView.model.isPresented)
        HUDWindow.shared.show(title: "音量", value: "17")
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(host.rootView.model.isPresented)
        XCTAssertEqual(host.rootView.model.level, 0.17)
    }

    func testHUDClosingCanBeInterruptedWithoutAnOldCompletionHidingTheNewValue() async throws {
        let _ = NSApplication.shared
        defer { HUDWindow.shared.stop() }
        HUDWindow.shared.show(title: "音量", value: "50")
        let panel = try XCTUnwrap(NSApp.windows.first { $0.contentView is NSHostingView<HUDView> })
        let host = try XCTUnwrap(panel.contentView as? NSHostingView<HUDView>)
        let closing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !host.rootView.model.isPresented }
        }, object: nil)
        await fulfillment(of: [closing], timeout: 3)
        HUDWindow.shared.show(title: "音量", value: "51")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(host.rootView.model.isPresented)
        XCTAssertEqual(host.rootView.model.value, "51")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !panel.isVisible }
        }, object: nil)
        await fulfillment(of: [hidden], timeout: 3)
        XCTAssertFalse(host.rootView.model.isPresented)
    }

    func testSidebarWidthAndNativeCollapseRecovery() async throws {
        let _ = NSApplication.shared
        let controller = NSHostingController(rootView: ToolboxPreviewGallery())
        let host = controller.view
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        await Task.yield()
        host.layoutSubtreeIfNeeded()
        func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
            (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
        }
        let split = try XCTUnwrap(descendants(host, of: NSSplitView.self).first { $0.isVertical })
        let sidebar = try XCTUnwrap(split.arrangedSubviews.first)
        let splitController = try XCTUnwrap(split.delegate as? NSSplitViewController)
        let sidebarItem = try XCTUnwrap(splitController.splitViewItems.first)
        func toggleSidebar(collapsed: Bool) async {
            let originalFrame = window.frame
            splitController.toggleSidebar(nil)
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { sidebarItem.isCollapsed == collapsed && sidebar.isHidden == collapsed }
            }, object: nil)
            await fulfillment(of: [settled], timeout: 2)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 0.5)
            XCTAssertEqual(window.frame.minX, originalFrame.minX, accuracy: 0.5)
        }
        XCTAssertGreaterThanOrEqual(sidebar.frame.width, 184)
        XCTAssertLessThanOrEqual(sidebar.frame.width, 220)
        for width in [1020.0, 1440.0] {
            window.setContentSize(NSSize(width: width, height: 820))
            host.layoutSubtreeIfNeeded()
            split.setPosition(196, ofDividerAt: 0)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            let frameBeforeDrag = window.frame
            let detailWidthBeforeDrag = split.arrangedSubviews[1].frame.width
            split.setPosition(0, ofDividerAt: 0)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            XCTAssertTrue(sidebarItem.isCollapsed)
            split.setPosition(196, ofDividerAt: 0)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.width, frameBeforeDrag.width, accuracy: 0.5)
            XCTAssertEqual(window.frame.minX, frameBeforeDrag.minX, accuracy: 0.5)
            XCTAssertEqual(split.arrangedSubviews[1].frame.width, detailWidthBeforeDrag, accuracy: 0.5)
            XCTAssertEqual(sidebar.frame.width, 196, accuracy: 0.5)
            XCTAssertFalse(sidebarItem.isCollapsed)
            XCTAssertFalse(sidebar.isHidden)
            for position in [900.0, 196.0, 160.0] {
                split.setPosition(position, ofDividerAt: 0)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(sidebar.frame.width, min(220, max(184, position)), accuracy: 0.5)
                XCTAssertFalse(sidebarItem.isCollapsed)
                XCTAssertFalse(sidebar.isHidden)
            }
            for position in [0.0, -300.0] {
                split.setPosition(position, ofDividerAt: 0)
                await Task.yield()
                host.layoutSubtreeIfNeeded()
                XCTAssertTrue(sidebarItem.isCollapsed)
                window.setContentSize(NSSize(width: width == 1020 ? 1440 : 1020, height: 820))
                await toggleSidebar(collapsed: false)
                XCTAssertFalse(sidebarItem.isCollapsed)
                XCTAssertFalse(sidebar.isHidden)
                XCTAssertGreaterThanOrEqual(sidebar.frame.width, 184)
                XCTAssertLessThanOrEqual(sidebar.frame.width, 220)
            }
            await toggleSidebar(collapsed: true)
            XCTAssertTrue(sidebarItem.isCollapsed)
            await toggleSidebar(collapsed: false)
            XCTAssertFalse(sidebarItem.isCollapsed)
            XCTAssertFalse(sidebar.isHidden)
        }
    }

    func testIntegratedSettingsPanesShareTheSessionWithoutQueryingTheDisplay() async {
        let _ = NSApplication.shared
        let runtime = PreviewRuntime(), state = runtime.makeState()
        let session = ToolboxSession(coordinator: state)
        defer { state.stop() }
        let originalSession = state.adb.session().sessionID
        let originalCommands = runtime.display.recordedCommands
        XCTAssertFalse(state.needsConnection(.settings))
        for pane in ToolboxSettingsPane.allCases {
            session.showSettings(pane)
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
            XCTAssertNil(window.attachedSheet)
        }
        let selectedPane = session.settingsPane
        session.showSettings()
        XCTAssertEqual(session.settingsPane, selectedPane)
    }

    func testNativeCandidateListOnlyEditsTheConnectionDraft() async throws {
        let _ = NSApplication.shared
        let runtime = PreviewRuntime(), state = runtime.makeState()
        defer { state.stop() }
        state.connection.scannedDevices = ["198.51.100.42", "203.0.113.7"]
        let session = state.adb.session(), commands = runtime.display.recordedCommands
        let originalHost = state.connection.ipInput
        let content = ConnectionSettingsView(connection: state.connection)
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

    func testParameterMenuUsesDomainValuesAndExternalUpdatesDoNotWrite() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        var commits = 0
        func menu(_ value: Int, enabled: Bool = true) -> ParameterMenu {
            ParameterMenu(title: "色域", options: OptionLists.gamut, selectedValue: value, isEnabled: enabled) {
                commits += 1
                state.setGamut($0)
            }
        }
        let control = menu(6)
        XCTAssertEqual(control.selection.wrappedValue, 6)
        XCTAssertEqual(commits, 0)
        control.selection.wrappedValue = 4 // AdobeRGB's domain value differs from its menu index.
        await state.waitForPendingWork()
        XCTAssertEqual(state.currentValues["tv_picture_advanced_video_color_space"], "4")
        XCTAssertEqual(commits, 1)
        let commands = runtime.display.recordedCommands
        XCTAssertEqual(menu(5).selection.wrappedValue, 5)
        XCTAssertEqual(menu(-1).selection.wrappedValue, -1)
        menu(-1).selection.wrappedValue = -1
        menu(6).selection.wrappedValue = 999
        menu(6, enabled: false).selection.wrappedValue = 4
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(runtime.display.recordedCommands, commands)
        state.stop()
    }

    func testGlassMenuUsesNativeButtonAndPreservesSelectionAcrossUpdates() throws {
        let _ = NSApplication.shared
        var value = "increase", enabled = true, commits = 0
        func content() -> some View {
            ToolboxGlassMenu(value, accessibilityLabel: "调整方向") {
                Picker("调整方向", selection: Binding(get: { value }, set: { value = $0; commits += 1 })) {
                    Text("增大").tag("increase")
                    Text("减小").tag("decrease")
                }.pickerStyle(.inline).labelsHidden()
            }.disabled(!enabled)
        }
        func findButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton { return button }
            return view.subviews.lazy.compactMap { findButton(in: $0) }.first
        }
        let host = NSHostingView(rootView: content())
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
        host.layoutSubtreeIfNeeded()
        let button = try XCTUnwrap(findButton(in: host))
        XCTAssertEqual(button.bezelStyle, .glass)
        XCTAssertEqual(button.borderShape, .capsule)
        XCTAssertEqual(button.focusRingType, .none)
        XCTAssertEqual(button.accessibilityRole(), .popUpButton)
        let item = try XCTUnwrap(button.menu?.items.first { $0.title == "减小" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(value, "decrease")
        XCTAssertEqual(commits, 1)
        value = "increase"
        host.rootView = content(); host.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.title, "increase")
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(button.menu?.items.first { $0.title == "增大" }?.state, .on)
        let popup = CapturingPopupMenu()
        let checked = NSMenuItem(title: "增大", action: nil, keyEquivalent: "")
        checked.state = .on
        popup.addItem(checked)
        button.menu = popup; button.title = "增大"
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(button.action), to: button.target, from: button))
        XCTAssertTrue(popup.positionedItem === checked)
        XCTAssertEqual(popup.location?.y, button.isFlipped ? button.bounds.minY : button.bounds.maxY)
        button.title = "更多"
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(button.action), to: button.target, from: button))
        XCTAssertNil(popup.positionedItem)
        XCTAssertEqual(popup.location?.y, button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4)
        enabled = false
        host.rootView = content(); host.layoutSubtreeIfNeeded()
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(try XCTUnwrap(button.menu?.items.first { $0.title == "减小" }).isEnabled)
        XCTAssertEqual(commits, 1)
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

private final class CapturingPopupMenu: NSMenu {
    var positionedItem: NSMenuItem?
    var location: NSPoint?
    override func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        positionedItem = item
        self.location = location
        return false
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
