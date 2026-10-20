#if canImport(Cocoa)
import XCTest
@testable import MimonitorToolbox

/// Opt-in: operates the real, already paired monitor at quiet volume, then restores it.
final class BluetoothHardwareTests: XCTestCase {
    /// Independent Android readback is an optional test oracle, never the control path.
    func testSinglePointStepsMatchDisplayReadback() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MIMONITOR_TEST_BLUETOOTH"] == "1")
        let environment = ProcessInfo.processInfo.environment
        guard let ip = environment["MIMONITOR_VERIFY_ADB_IP"],
              let path = environment["MIMONITOR_TEST_ADB_PATH"] else { throw XCTSkip("Optional read-only ADB verifier not configured") }
        let verifier = AdbClient(adbPath: path, serverPort: "5041")
        verifier.ip = ip
        XCTAssertTrue(verifier.ensureConnected().ok)
        let access = CoreAudioBluetoothVolumeAccess()
        let control = BluetoothVolumeController(access: access)
        let device = try XCTUnwrap(control.device(named: environment["MIMONITOR_BLUETOOTH_NAME"] ?? "REDMI G Pro 32U 2026"))
        let original = try device.channels.map { try access.read(device, channel: $0) }
        // A previous test's CoreAudio writes may still be in the Bluetooth queue.
        // Capture the baseline only after the display reaches the current scalar value.
        let expectedOriginal = BluetoothVolumeScale.volume(forScalar: try XCTUnwrap(original.first))
        let settleDeadline = Date().addingTimeInterval(2)
        var observed = verifier.mediaVolume()
        while observed != expectedOriginal && Date() < settleDeadline {
            Thread.sleep(forTimeInterval: 0.02)
            observed = verifier.mediaVolume()
        }
        let originalDisplay = try XCTUnwrap(observed)
        XCTAssertEqual(originalDisplay, expectedOriginal, "baseline must settle before testing")
        guard originalDisplay == expectedOriginal else { return }
        try XCTSkipUnless(originalDisplay <= 25, "Start at a quiet volume (0–25)")
        let output = AudioOutputMonitor.defaultOutputDeviceName()
        func verify(_ expected: Int) {
            let deadline = Date().addingTimeInterval(1)
            var actual = verifier.mediaVolume()
            while actual != expected && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
                actual = verifier.mediaVolume()
            }
            XCTAssertEqual(actual, expected, "display volume \(expected)")
        }
        defer {
            for (index, channel) in device.channels.enumerated() {
                try? access.write(device, channel: channel, scalar: original[index])
            }
            verify(originalDisplay)
        }
        _ = try control.setVolume(0, on: device)
        verify(0)
        for value in 1...20 {
            XCTAssertEqual(try control.adjust(increase: true, nativeSteps: false, step: 1, on: device).volume, value)
            verify(value)
        }
        for value in stride(from: 19, through: 0, by: -1) {
            XCTAssertEqual(try control.adjust(increase: false, nativeSteps: false, step: 1, on: device).volume, value)
            verify(value)
        }
        _ = try control.setVolume(8, on: device)
        _ = try control.toggleMute(on: device)
        verify(0)
        _ = try control.toggleMute(on: device)
        verify(8)
        XCTAssertEqual(AudioOutputMonitor.defaultOutputDeviceName(), output)
    }

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
