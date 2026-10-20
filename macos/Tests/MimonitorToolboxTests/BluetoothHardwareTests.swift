#if canImport(Cocoa)
import XCTest
@testable import MimonitorToolbox

/// Opt-in: operates the real, already paired monitor at quiet volume, then restores it.
final class BluetoothHardwareTests: XCTestCase {
    func testBluetoothVolumeWithoutADBAndWithoutChangingAudioOutput() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MIMONITOR_TEST_BLUETOOTH"] == "1")
        let access = CoreAudioBluetoothVolumeAccess()
        let control = BluetoothVolumeController(access: access)
        let name = ProcessInfo.processInfo.environment["MIMONITOR_BLUETOOTH_NAME"] ?? "REDMI G Pro 32U 2026"
        let device = try XCTUnwrap(control.device(named: name))
        let output = AudioOutputMonitor.defaultOutputDeviceName()
        let original = try device.channels.map { try access.read(device, channel: $0) }
        try XCTSkipUnless(original.allSatisfy { $0 <= 0.25 }, "Start at a quiet volume (0–25%)")
        defer {
            for (index, channel) in device.channels.enumerated() {
                try? access.write(device, channel: channel, scalar: original[index])
            }
        }
        XCTAssertTrue(AudioOutputMonitor.shouldHandleVolumeKeys(enabled: true, bluetoothAvailable: true,
            adbConnected: false, gateEnabled: true, configuredOutputName: "Mi Monitor",
            bluetoothOutputName: name, outputName: output))
        _ = try control.setVolume(6, on: device)
        XCTAssertEqual(try control.state(device).volume, 6)
        XCTAssertEqual(try control.adjust(increase: true, nativeSteps: true, step: 5, on: device).volume, 13)
        XCTAssertEqual(try control.adjust(increase: false, nativeSteps: true, step: 5, on: device).volume, 6)
        XCTAssertTrue(try control.toggleMute(on: device).muted)
        XCTAssertFalse(try control.toggleMute(on: device).muted)
        XCTAssertEqual(try control.state(device).volume, 6)
        XCTAssertEqual(AudioOutputMonitor.defaultOutputDeviceName(), output)
    }
}
#endif
