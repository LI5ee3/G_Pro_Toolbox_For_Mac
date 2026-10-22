import ToolboxDomain
import ToolboxApplication
#if canImport(Cocoa)
import XCTest
@testable import MimonitorToolbox

/// 亮度步进的「首次对齐」逻辑：不在格点上时先跳到方向上的最近格点。
final class StepAlignTests: XCTestCase {
    func testAlignsUpToNextMultipleOnIncrease() {
        XCTAssertEqual(ControlStep.alignToStep(6, step: 10, increasing: true), 10)
    }

    func testStepsNormallyWhenAlreadyOnGrid() {
        XCTAssertEqual(ControlStep.alignToStep(10, step: 10, increasing: true), 20)
    }

    func testAlignsDownToPreviousMultipleOnDecrease() {
        XCTAssertEqual(ControlStep.alignToStep(15, step: 10, increasing: false), 10)
        XCTAssertEqual(ControlStep.alignToStep(6, step: 10, increasing: false), 0)
    }

    func testZeroIsOnGrid() {
        XCTAssertEqual(ControlStep.alignToStep(0, step: 10, increasing: true), 10)
    }

    func testStepOneAlwaysSteps() {
        XCTAssertEqual(ControlStep.alignToStep(6, step: 1, increasing: true), 7)
        XCTAssertEqual(ControlStep.alignToStep(6, step: 1, increasing: false), 5)
    }
}
#endif
