#if canImport(Cocoa)
import XCTest
@testable import MimonitorToolbox

final class BluetoothVolumeTests: XCTestCase {
    private final class FakeAccess: BluetoothVolumeAccess {
        let display = BluetoothVolumeDevice(id: 1, uid: "monitor", name: "REDMI G Pro 32U 2026", channels: [1, 2])
        var listed: [BluetoothVolumeDevice] = []
        var values: [UInt32: Float32] = [1: 0, 2: 0]
        var failingChannel: UInt32?
        init() { listed = [display] }
        func devices() throws -> [BluetoothVolumeDevice] { listed }
        func read(_ device: BluetoothVolumeDevice, channel: UInt32) throws -> Float32 { values[channel]! }
        func write(_ device: BluetoothVolumeDevice, channel: UInt32, scalar: Float32) throws {
            if channel == failingChannel { throw BluetoothVolumeController.Failure.unavailable }
            values[channel] = scalar
        }
    }

    func testOnlyExactUnambiguousWritableDeviceNameIsSelected() {
        let access = FakeAccess(), controller = BluetoothVolumeController(access: FakeAccess())
        XCTAssertNotNil(controller.device(named: " redmi g pro 32u 2026 "))
        XCTAssertNil(controller.device(named: "REDMI"))
        XCTAssertNil(controller.device(named: ""))
        access.listed.append(BluetoothVolumeDevice(id: 2, uid: "other", name: access.display.name, channels: [1]))
        XCTAssertNil(BluetoothVolumeController(access: access).device(named: access.display.name))
        access.listed = [BluetoothVolumeDevice(id: 3, uid: "readonly", name: access.display.name, channels: [])]
        XCTAssertNil(BluetoothVolumeController(access: access).device(named: access.display.name))
    }

    func testNativeVolumeStepsKeepStereoChannelsTogether() throws {
        let access = FakeAccess()
        let control = BluetoothVolumeController(access: access)
        XCTAssertEqual(try control.adjust(increase: true, nativeSteps: true, step: 5, on: access.display).volume, 6)
        XCTAssertEqual(try control.adjust(increase: true, nativeSteps: true, step: 5, on: access.display).volume, 13)
        XCTAssertEqual(try control.adjust(increase: false, nativeSteps: true, step: 5, on: access.display).volume, 6)
        XCTAssertEqual(access.values[1], access.values[2])
        XCTAssertEqual(try control.adjust(increase: false, nativeSteps: true, step: 5, on: access.display), BluetoothVolumeState(volume: 0, muted: true))
        XCTAssertEqual(try control.adjust(increase: true, nativeSteps: true, step: 5, on: access.display).volume, 6)
    }

    func testMuteSurvivesPollingAndRestoresAudibleVolume() throws {
        let access = FakeAccess()
        let controller = BluetoothVolumeController(access: access)
        _ = try controller.setVolume(38, on: access.display)
        XCTAssertTrue(try controller.toggleMute(on: access.display).muted)
        XCTAssertEqual(access.values[1], 0)
        XCTAssertEqual(access.values[2], 0)
        XCTAssertEqual(try controller.state(access.display), BluetoothVolumeState(volume: 38, muted: true))
        XCTAssertEqual(try controller.toggleMute(on: access.display), BluetoothVolumeState(volume: 38, muted: false))
    }

    func testUnmuteUnknownZeroUsesQuietStartingVolume() throws {
        let access = FakeAccess()
        XCTAssertEqual(try BluetoothVolumeController(access: access).toggleMute(on: access.display), BluetoothVolumeState(volume: 6, muted: false))
    }

    func testFailedSecondChannelWriteRestoresFirstChannel() throws {
        let access = FakeAccess()
        access.values = [1: 0.25, 2: 0.25]
        access.failingChannel = 2
        XCTAssertThrowsError(try BluetoothVolumeController(access: access).setVolume(31, on: access.display))
        XCTAssertEqual(access.values[1], 0.25)
        XCTAssertEqual(access.values[2], 0.25)
    }

    func testInvalidReadDoesNotGuessOrWriteVolume() {
        let access = FakeAccess()
        access.values[1] = .nan
        XCTAssertThrowsError(try BluetoothVolumeController(access: access).adjust(increase: true, nativeSteps: true, step: 5, on: access.display))
        XCTAssertEqual(access.values[2], 0)
    }

    func testAll101DisplayValuesSurviveBothBluetoothConversionsExactly() {
        var previousWire = -1
        for value in 0...100 {
            let scalar = BluetoothVolumeScale.scalar(forVolume: value)
            // Actual wire model, independent of the production decoder and its tolerance.
            let wire = Int((Double(scalar) * 127).rounded(.down))
            let display = Int((Double(wire) * 100 / 127).rounded())
            XCTAssertEqual(display, value, "wire round trip at \(value)")
            XCTAssertEqual(BluetoothVolumeScale.volume(forScalar: scalar), value)
            XCTAssertGreaterThan(wire, previousWire)
            previousWire = wire
        }
    }

    func testIncomingWireNotificationsDecodeDespiteFloat32Boundaries() {
        for wire in 0...127 {
            XCTAssertEqual(BluetoothVolumeScale.volume(forScalar: Float32(Double(wire) / 127)),
                           Int((Double(wire) * 100 / 127).rounded()), "wire \(wire)")
        }
    }

    func testExternalTenPercentStartsAtActualNineThenMovesOnePoint() throws {
        let access = FakeAccess()
        access.values = [1: 0.10, 2: 0.10]
        let controller = BluetoothVolumeController(access: access)
        XCTAssertEqual(try controller.state(access.display).volume, 9)
        XCTAssertEqual(try controller.adjust(increase: true, nativeSteps: false, step: 1, on: access.display).volume, 10)
        XCTAssertEqual(try controller.adjust(increase: true, nativeSteps: false, step: 1, on: access.display).volume, 11)
        XCTAssertEqual(try controller.adjust(increase: false, nativeSteps: false, step: 1, on: access.display).volume, 10)
    }

    func testOnePointSequenceHasNoPlateausOrSkipsAcrossEntireRange() throws {
        let access = FakeAccess()
        let control = BluetoothVolumeController(access: access)
        for value in 1...100 {
            XCTAssertEqual(try control.adjust(increase: true, nativeSteps: false, step: 1, on: access.display).volume, value)
        }
        XCTAssertEqual(try control.adjust(increase: true, nativeSteps: false, step: 1, on: access.display).volume, 100)
        for value in stride(from: 99, through: 0, by: -1) {
            XCTAssertEqual(try control.adjust(increase: false, nativeSteps: false, step: 1, on: access.display).volume, value)
        }
        XCTAssertEqual(try control.adjust(increase: false, nativeSteps: false, step: 1, on: access.display).volume, 0)
    }

    func testOutputGateAllowsBluetoothWithoutADBButProtectsOtherSpeakers() {
        func gate(_ output: String?, bt: Bool = true, adb: Bool = false, enabled: Bool = true) -> Bool {
            AudioOutputMonitor.shouldHandleVolumeKeys(enabled: enabled, bluetoothAvailable: bt, adbConnected: adb,
                gateEnabled: true, configuredOutputName: "Mi Monitor", bluetoothOutputName: "REDMI G Pro 32U 2026", outputName: output)
        }
        XCTAssertTrue(gate("Mi Monitor"))
        XCTAssertTrue(gate("REDMI G Pro 32U 2026"))
        XCTAssertFalse(gate("AirPods"))
        XCTAssertFalse(gate("Mac mini扬声器"))
        XCTAssertFalse(gate(nil))
        XCTAssertFalse(gate("Mi Monitor", bt: false))
        XCTAssertTrue(gate("Mi Monitor", bt: false, adb: true))
        XCTAssertFalse(gate("Mi Monitor", enabled: false))
    }
}
#endif
