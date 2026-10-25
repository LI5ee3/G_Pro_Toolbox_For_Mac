import ToolboxDomain
import ToolboxApplication
import XCTest
import MimonitorPresetCore
@testable import MimonitorToolbox
@testable import ToolboxPreviewSupport

@MainActor
final class CoordinatorRegressionTests: XCTestCase {
    private func drain(_ state: AppCoordinator) async {
        let done = expectation(description: "device work and main publication complete")
        state.deviceQueue.async { DispatchQueue.main.async { done.fulfill() } }
        await fulfillment(of: [done], timeout: 3)
    }

    func testPresetCreatePublishesConfigurationAndNavigationAndReleasesBusyState() async throws {
        let state = PreviewRuntime().makeState()
        state.createPreset(name: "工作")
        XCTAssertTrue(state.presets.isPresetOperationInFlight)
        await drain(state)
        XCTAssertEqual(state.presets.presetConfiguration.presets.map(\.name), ["工作"])
        XCTAssertEqual(state.navigation.requestedPage, .picture)
        XCTAssertFalse(state.presets.isPresetOperationInFlight)
        XCTAssertFalse(state.presets.isPresetBusy)
        XCTAssertNil(state.presets.presetError)
    }

    func testFailedPresetApplyPreservesPresetAndPublishesErrorWithoutRemainingBusy() async throws {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.createPreset(name: "测试"); await drain(state)
        let id = try XCTUnwrap(state.presets.presetConfiguration.presets.first?.id)
        runtime.display.failWrites = true
        state.applyPreset(id: id); await drain(state)
        XCTAssertEqual(state.presets.presetConfiguration.presets.first?.id, id)
        XCTAssertNotNil(state.presets.presetError)
        XCTAssertFalse(state.presets.isPresetOperationInFlight)
        XCTAssertFalse(state.presets.isPresetBusy)
    }

}
