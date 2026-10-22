import ToolboxDomain
import ToolboxApplication
import Foundation
import XCTest
@testable import MimonitorToolbox

final class AdbClientTests: XCTestCase {
    func testAbsoluteVolumeUsesExistingBinderAndVerifiesTheFirstWrite() throws {
        try fake("""
        printf '%s\\n' "$4" >> "$0.calls"
        case "$4" in
          'service call audio 12 i32 3 i32 27 i32 0 s16 com.android.shell') echo 'Result: Parcel(00000000)' ;;
          'service call audio 22 i32 3') echo 'Result: Parcel(00000000 0000001b)' ;;
          *) exit 9 ;;
        esac
        """) { client in
            XCTAssertTrue(client.setMediaVolume(27))
            let calls = try String(contentsOfFile: client.adbPath + ".calls", encoding: .utf8)
            XCTAssertEqual(calls.split(separator: "\n").count, 2)
            XCTAssertFalse(calls.contains("input keyevent"))
        }
    }

    func testBinderFailureKeepsExistingKeyEventVolumeFallback() throws {
        try fake("""
        printf '%s\\n' "$4" >> "$0.calls"
        case "$4" in
          'service call audio 12 '*) echo 'Parcel: Exception occurred' ;;
          'service call audio 22 i32 3') echo 'Result: Parcel(00000000 0000000a)' ;;
          'input keyevent KEYCODE_VOLUME_UP KEYCODE_VOLUME_UP') ;;
          *) exit 9 ;;
        esac
        """) { client in
            XCTAssertFalse(client.setMediaVolume(12))
            let calls = try String(contentsOfFile: client.adbPath + ".calls", encoding: .utf8)
            XCTAssertTrue(calls.contains("input keyevent KEYCODE_VOLUME_UP KEYCODE_VOLUME_UP"))
        }
    }

    func testMuteUsesExistingBinderAndHardwareReadback() throws {
        try fake("""
        case "$4" in
          'service call audio 10 i32 3 i32 -100 i32 0 s16 com.android.shell') echo 'Result: Parcel(00000000)' ;;
          'service call audio 17 i32 3') echo 'Result: Parcel(00000000 00000001)' ;;
          *) exit 9 ;;
        esac
        """) { client in XCTAssertTrue(client.setMediaMuted(true)) }
    }

    func testDeviceStateAloneDoesNotProveTransportIsUsable() throws {
        try fake("""
        case "$3" in
          get-state) echo device ;;
          shell) echo 'error: device offline'; exit 1 ;;
          *) exit 2 ;;
        esac
        """) { client in
            XCTAssertEqual(client.deviceState(), "device")
            XCTAssertFalse(client.transportWorks())
        }
    }

    func testEnsureConnectedRepairsStaleTransportReportedAsDevice() throws {
        try fake("""
        marker="$0.connected"
        case "$1" in
          connect)
            [ "$2" = "192.168.1.20:5555" ] || exit 2
            touch "$marker"
            echo connected ;;
          -s)
            [ "$2" = "192.168.1.20:5555" ] || exit 2
            case "$3" in
              get-state) echo device ;;
              shell)
                if [ -f "$marker" ]; then echo __mimonitor_probe__
                else echo 'error: device offline'; exit 1; fi ;;
              *) exit 3 ;;
            esac ;;
          *) exit 4 ;;
        esac
        """) { client in
            XCTAssertFalse(client.transportWorks())
            let result = client.ensureConnected()
            XCTAssertTrue(result.ok)
            XCTAssertEqual(result.state, "device")
            XCTAssertTrue(client.transportWorks())
        }
    }

    func testScanProbeReadsModelFromExplicitTargetAndLeavesCurrentIpUnchanged() throws {
        try fake("""
        case "$1" in
          connect|disconnect) [ "$2" = "192.168.1.40:5555" ] || exit 2 ;;
          -s)
            [ "$2" = "192.168.1.40:5555" ] || exit 2
            case "$3" in
              get-state) echo device ;;
              shell) echo MiTV-Monitor ;;
            esac ;;
          *) exit 2 ;;
        esac
        """) { client in
            let device = client.probeScannedDevice(ip: "192.168.1.40")
            XCTAssertEqual(device, ScannedDevice(ip: "192.168.1.40", model: "MiTV-Monitor"))
            XCTAssertEqual(client.ip, "192.168.1.20")
        }
    }

    func testScanProbeRejectsUnauthorizedAndFailedModelReads() throws {
        try fake("""
        case "$3" in
          get-state) echo unauthorized ;;
          shell) echo MiTV-Monitor ;;
        esac
        """) { client in XCTAssertNil(client.probeScannedDevice(ip: "192.168.1.40")) }
        try fake("""
        case "$3" in
          get-state) echo device ;;
          shell) echo 'error: device offline'; exit 1 ;;
        esac
        """) { client in XCTAssertNil(client.probeScannedDevice(ip: "192.168.1.40")) }
    }
    private func fake(_ script: String, test: (AdbClient) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preset-adb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("adb")
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let client = AdbClient(adbPath: executable.path)
        client.ip = "192.168.1.20"
        try test(client)
    }

    func testCheckedShellRejectsNonzeroExitAndBinderExceptions() throws {
        try fake("echo 'device offline'; exit 1\n") { client in
            XCTAssertThrowsError(try client.checkedShell("settings list global", target: "192.168.1.20:5555"))
        }
        try fake("echo 'Parcel: Exception occurred'; exit 0\n") { client in
            XCTAssertThrowsError(try client.checkedShell("service call TvService", target: "192.168.1.20:5555"))
        }
    }

    func testCheckedShellUsesCapturedTargetNotChangedIp() throws {
        try fake("printf '%s\\n' \"$@\"\n") { client in
            client.ip = "192.168.1.30"
            let output = try client.checkedShell("echo test", target: "192.168.1.20:5555")
            XCTAssertTrue(output.contains("192.168.1.20:5555"))
            XCTAssertFalse(output.contains("192.168.1.30:5555"))
        }
    }

    func testTransactionPreventsCommandsFromInterleavingWithPresetBatch() throws {
        try fake("printf '%s\\n' \"$@\"\n") { client in
            let lock = NSLock()
            var order: [String] = []
            let started = DispatchSemaphore(value: 0)
            let contenderStarted = DispatchSemaphore(value: 0)
            let finished = DispatchGroup()
            finished.enter()
            DispatchQueue.global().async {
                client.transaction {
                    _ = client.shell("first")
                    lock.lock(); order.append("first"); lock.unlock()
                    started.signal()
                    contenderStarted.wait()
                    Thread.sleep(forTimeInterval: 0.05)
                    _ = client.shell("second")
                    lock.lock(); order.append("second"); lock.unlock()
                }
                finished.leave()
            }
            finished.enter()
            DispatchQueue.global().async {
                started.wait()
                contenderStarted.signal()
                _ = client.shell("contender")
                lock.lock(); order.append("contender"); lock.unlock()
                finished.leave()
            }
            XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
            XCTAssertEqual(order, ["first", "second", "contender"])
        }
    }

    func testDisconnectUsesCapturedTargetAfterCurrentIpWasCleared() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimonitor-adb-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeAdb = directory.appendingPathComponent("adb")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\"\n".write(to: fakeAdb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeAdb.path)

        let client = AdbClient(adbPath: fakeAdb.path)
        client.ip = ""

        XCTAssertEqual(client.disconnect(ip: "192.168.1.20"), "disconnect\n192.168.1.20:5555\n")
    }
}
