import AppKit
import SwiftUI
import XCTest
import ToolboxApplication
import ToolboxDomain
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class PreviewRenderingTests: XCTestCase {
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
        func content() -> some View {
            ToolsView().environment(\.toolboxActions, state).environment(state.connection)
                .environment(state.tools).environment(state.keyboard).environment(state.settings)
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
