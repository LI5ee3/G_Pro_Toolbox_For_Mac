import XCTest
import SwiftUI
import ToolboxDomain
import MimonitorPresetCore

final class DomainContractTests: XCTestCase {
    func testFirmwareColorAndHDRMappingsRemainExact() {
        XCTAssertEqual(PicturePresetPlan.colorTempToMtk, [0: 1, 1: 2, 2: 3, 3: 0, 4: 4, 5: 5, 8: 6])
        XCTAssertEqual(PicturePresetPlan.hdrToneMappingToMtk, [0: 5, 1: 0, 2: 2, 3: 1])
        for (ui, hardware) in PicturePresetPlan.colorTempToMtk {
            let values = PicturePresetPlan.normalize(settings: [:], jni: ["g_video__clr_temp": String(hardware)], source: "29")
            XCTAssertEqual(values["picture_color_temperature"], String(ui))
            XCTAssertEqual(RegisterMap.mtkToColorTemp[hardware], ui)
        }
    }

    func testHDRNormalizationAndDisplayMappingAgreeForEverySupportedValue() {
        for (ui, hardware) in PicturePresetPlan.hdrToneMappingToMtk {
            let values = PicturePresetPlan.normalize(settings: [:], jni: ["g_video__vid_hdr_tone_mapping_mode": String(hardware)], source: "29")
            XCTAssertEqual(values["settings_display_hdr_color_tone"], String(ui))
            XCTAssertEqual(RegisterMap.hdrToneMappingMtkToUI[hardware], ui)
        }
        XCTAssertFalse(RegisterMap.isHDRPictureMode("14"))
        XCTAssertTrue(RegisterMap.isHDRPictureMode("44"))
        XCTAssertFalse(RegisterMap.isHDRPictureMode("null"))
        XCTAssertEqual(RegisterMap.hdrToneMappingPictureModes, PicturePresetPlan.hdrModes)
    }

    func testBacklightBoundsRejectZeroWithoutSilentlyClamping() {
        var commands: [PresetCommand] = []
        _ = PicturePresetPlan.apply(["picture_backlight": "0"], source: "29") { commands.append($0) }
        XCTAssertFalse(commands.contains { if case .jni("g_disp__disp_back_light", _, _) = $0 { return true }; return false })
        for value in [ControlRanges.backlight.lowerBound, ControlRanges.backlight.upperBound] {
            commands = []
            _ = PicturePresetPlan.apply(["picture_backlight": String(value)], source: "29") { commands.append($0) }
            XCTAssertTrue(commands.contains(.jni("g_disp__disp_back_light", String(value), 3)))
        }
    }

    func testGainBoundsKeepFullHardwareRange() {
        for value in [523, 524, 1524, 1525] {
            var commands: [PresetCommand] = []
            let text = String(value)
            _ = PicturePresetPlan.apply(["picture_color_temperature": "3", "picture_red_gain": text,
                                         "picture_green_gain": text, "picture_blue_gain": text], source: "29") { commands.append($0) }
            XCTAssertEqual(commands.contains(.colorGains(text, text, text)), ControlRanges.colorGain.contains(value))
        }
    }

    func testMenuBarNumericControlsKeepTheirRangesAndSteps() throws {
        for id in ["backlight", "black_level", "contrast", "saturation", "hue", "sharpness"] {
            let entry = try XCTUnwrap(MenuBarCatalog.entry(id))
            guard case .stepper(let min, let max, let step) = entry.kind else { return XCTFail("numeric entry changed") }
            XCTAssertEqual(min, id == "backlight" ? 1 : 0)
            XCTAssertEqual(max, 100)
            XCTAssertEqual(step, id == "sharpness" ? 1 : 5)
        }
        XCTAssertEqual(ControlRanges.screenLightUI, 1...15)
        XCTAssertEqual(ControlRanges.screenLightDevice, 0...14)
    }

    func testFoundationReorderingMatchesSwiftUIForAllSmallSelections() {
        for count in 0...6 {
            let original = Array(0..<count)
            for mask in 0..<(1 << count) {
                let offsets = IndexSet((0..<count).filter { mask & (1 << $0) != 0 })
                for destination in 0...count {
                    var expected = original
                    expected.move(fromOffsets: offsets, toOffset: destination)
                    XCTAssertEqual(OrderedItems.move(original, from: offsets, to: destination), expected,
                                   "count=\(count) mask=\(mask) destination=\(destination)")
                }
            }
        }
    }
}
