import ToolboxApplication
#if canImport(Cocoa)
import Carbon.HIToolbox
import CoreGraphics
import XCTest

final class HotkeyMapTests: XCTestCase {
    // Expected values come directly from the SDK, independently of HotkeyMap.
    private let functionKeys: [(String, Int)] = [
        ("F1", kVK_F1), ("F2", kVK_F2), ("F3", kVK_F3),
        ("F4", kVK_F4), ("F5", kVK_F5), ("F6", kVK_F6),
        ("F7", kVK_F7), ("F8", kVK_F8), ("F9", kVK_F9),
        ("F10", kVK_F10), ("F11", kVK_F11), ("F12", kVK_F12),
    ]

    private let arrowKeys: [(String, Int)] = [
        ("↑", kVK_UpArrow), ("↓", kVK_DownArrow),
        ("←", kVK_LeftArrow), ("→", kVK_RightArrow),
    ]

    func testFunctionKeyCodesMatchSDKConstants() {
        for (name, code) in functionKeys {
            XCTAssertEqual(HotkeyMap.keyCode(for: name), CGKeyCode(code), name)
        }
    }

    func testFunctionKeyNamesMatchSDKConstants() {
        for (name, code) in functionKeys {
            XCTAssertEqual(HotkeyMap.keyName(for: CGKeyCode(code)), name, name)
        }
    }

    func testArrowKeyCodesMatchSDKConstants() {
        for (name, code) in arrowKeys {
            XCTAssertEqual(HotkeyMap.keyCode(for: name), CGKeyCode(code), name)
        }
    }

    func testArrowKeyNamesMatchSDKConstants() {
        for (name, code) in arrowKeys {
            XCTAssertEqual(HotkeyMap.keyName(for: CGKeyCode(code)), name, name)
        }
    }
}
#endif
