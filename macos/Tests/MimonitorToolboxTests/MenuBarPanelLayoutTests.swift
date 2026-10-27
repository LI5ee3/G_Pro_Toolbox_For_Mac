import AppKit
import ToolboxDomain
import ToolboxApplication
import XCTest
@testable import MimonitorToolbox

final class MenuBarPanelLayoutTests: XCTestCase {
    func testShortPresetRowsFillTheAvailableWidthRatherThanTheirIntrinsicWidth() {
        for count in [1, 2, 3, 4] {
            XCTAssertEqual(MenuBarPanelLayout.presetWidth(count: count), 292)
        }
        XCTAssertEqual(MenuBarPanelLayout.presetWidth(count: 5), 400)
    }

    func testPanelFitsItsContentAndScrollsOnlyWhenItReachesTheHeightLimit() {
        XCTAssertEqual(MenuBarPanelLayout.scrollHeight(contentHeight: 64), 64)
        XCTAssertEqual(MenuBarPanelLayout.scrollHeight(contentHeight: 180), 180)
        XCTAssertEqual(MenuBarPanelLayout.scrollHeight(contentHeight: 900), 420)
        XCTAssertEqual(MenuBarPanelLayout.scrollHeight(contentHeight: 0), 1)
    }

    @MainActor func testHUDStaysBelowItsMenuBarIconAndInsideTheScreenEdges() {
        let area = NSRect(x: 0, y: 30, width: 1440, height: 846)
        XCTAssertEqual(HUDWindow.origin(anchor: NSRect(x: 980, y: 876, width: 24, height: 24), in: area),
                       NSPoint(x: 838, y: 802))
        XCTAssertEqual(HUDWindow.origin(anchor: NSRect(x: 1410, y: 876, width: 24, height: 24), in: area).x, 1124)
        XCTAssertEqual(HUDWindow.origin(anchor: NSRect(x: 0, y: 876, width: 24, height: 24), in: area).x, 8)
        XCTAssertEqual(HUDWindow.origin(anchor: nil, in: area), NSPoint(x: 1124, y: 802))
        let secondary = NSRect(x: -1920, y: -1050, width: 1920, height: 1026)
        XCTAssertEqual(HUDWindow.origin(anchor: NSRect(x: -500, y: -24, width: 24, height: 24), in: secondary),
                       NSPoint(x: -642, y: -98))
    }

    func testHUDProgressKeepsSingleVolumeUnitsAndDoesNotTreatUnknownValuesAsZero() {
        let model = HUDModel(title: "音量")
        for (value, expected) in [(0, 0.0), (1, 0.01), (16, 0.16), (17, 0.17), (99, 0.99), (100, 1.0)] {
            model.value = String(value)
            XCTAssertEqual(model.level, expected)
        }
        for value in ["—", "-1", "101"] {
            model.value = value
            XCTAssertNil(model.level)
        }
        model.title = "静音"; model.value = "开"
        XCTAssertEqual(model.symbolName, "speaker.slash.fill")
        XCTAssertEqual(model.level, 0)
        model.value = "关"
        XCTAssertNil(model.level)
        XCTAssertEqual(model.symbolName, "speaker.wave.3.fill")
        model.title = "背光"; model.value = "50"
        XCTAssertEqual(model.level, 0.5)
        model.operationPhase = .running
        XCTAssertNil(model.level)
    }

    func testHUDInterpolationKeepsFractionalFramesSeparateFromTheIntegerTarget() {
        let model = HUDModel(title: "音量", value: "51")
        var level = HUDLevel(value: 50)
        level.animatableData = 50.4
        XCTAssertEqual(level.value, 50.4)
        XCTAssertEqual(model.value, "51")
        XCTAssertEqual(model.level, 0.51)
        level.animatableData = -1
        XCTAssertEqual(level.value, 0)
        level.animatableData = 101
        XCTAssertEqual(level.value, 100)
    }

    @MainActor func testDashboardAndHUDVolumeSymbolsMatchAllThreeBandsAndTheirBoundaries() {
        let model = HUDModel(title: "音量")
        for (volume, symbol) in [(0, "speaker.slash.fill"), (1, "speaker.wave.1.fill"),
                                 (33, "speaker.wave.1.fill"), (34, "speaker.wave.2.fill"),
                                 (66, "speaker.wave.2.fill"), (67, "speaker.wave.3.fill"),
                                 (100, "speaker.wave.3.fill")] {
            model.value = String(volume)
            XCTAssertEqual(model.symbolName, symbol)
            XCTAssertEqual(VolumeSymbol.name(for: volume), symbol)
            XCTAssertEqual(VolumeSymbol.name(for: volume, muted: true), "speaker.slash.fill")
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil))
        }
        XCTAssertEqual(VolumeSymbol.name(for: nil), "speaker.wave.3.fill")
        XCTAssertEqual(VolumeSymbol.name(for: nil, muted: true), "speaker.slash.fill")
    }
}
