import Foundation
import XCTest
import ToolboxConcurrency
import ToolboxDomain
import ToolboxMacAdapters
import MimonitorPresetCore
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

/// Real coordinator/client/adapter, with only process and OS effects replaced by existing Preview fakes.
@MainActor
private final class RoutingFixture {
    let runtime = PreviewRuntime()
    let state: AppCoordinator
    // Read/reset only after waitForPendingWork; execution is serialized by the client.
    var requests: [CommandRequest] { trace.requests }
    var scripts: [String] { trace.scripts }
    var probes: [String] { trace.probes }
    private let trace: Trace
    private final class Trace {
        var requests: [CommandRequest] = []
        var scripts: [String] = []
        var probes: [String] = []
    }
    static let usb: AdbEndpoint = {
        guard case .complete(let devices) = AdbDeviceListParser.parse(
            "List of devices attached\n000RoutingUSB device usb:fixture\n") else { fatalError("fixture") }
        return AdbEndpoint.usb(discovered: devices[0])!
    }()
    static let tcp = AdbEndpoint.tcp(host: "192.0.2.27", port: 5567)!
    static var endpoints: [AdbEndpoint] { [usb, tcp] }
    static let owner = "device:11111111-2222-3333-4444-555555555555"
    static let adbPath = "/fake/O'Brien \"ADB\"/adb"

    init(_ endpoint: AdbEndpoint?, intercept: ((CommandRequest) -> ProcessResult?)? = nil) {
        let trace = Trace(); self.trace = trace
        runtime.display.configureDiscovery(rows: "000RoutingUSB device usb:fixture model:MiTV_Fixture")
        let base = runtime.environment(), display = runtime.display
        let adb = AdbClient(resources: RuntimeResources(adbPath: Self.adbPath, serverPort: "5038",
            runtime: { "/fake/\($0)" }, guardianAPK: { "/fake/guardian.apk" }, fileSize: { _ in 4096 })) { request in
                trace.requests.append(request)
                return intercept?(request) ?? display.execute(request)
            }
        var system = base.system
        system.terminal = { script, _ in trace.scripts.append(script); return TerminalResult(outcome: .opened) }
        system.subnets = { ["192.0.2"] }
        system.ping = { trace.probes.append("ping \($0)"); return true }
        system.tcpOpen = { host, port, timeout in
            trace.probes.append("tcp \(host):\(port) \(timeout)"); return true
        }
        state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: system, now: base.now,
            presetDevice: { AdbPresetDevice(adb: $0, endpoint: $1, identity: $2) }))
        adb.beginSession(endpoint: endpoint)
        state.connection.activeEndpoint = endpoint
        state.connectionStatus = endpoint == nil ? .disconnected : .connected("fixture")
        state.seedSimulationReadings(volume: 10, muted: false)
        state.currentValues = display.values
        state.hotkeyCountdownEnabled = false
    }
    func clear() { trace.requests.removeAll(); trace.scripts.removeAll(); trace.probes.removeAll() }
    func confirmFixtureIdentity() {
        state.connection.identityRestricted = false
        state.connection.presetIdentityKey = Self.owner
        state.connection.allowsIdentityAutomaticActions = true
    }
}

@MainActor
final class ToolSessionRoutingTests: XCTestCase {
    func testDiagnosticsUsesSubmittedTCPInputAndActualDevicePort() async {
        let f = RoutingFixture(RoutingFixture.tcp), s = f.state
        s.ipInput = "192.0.2.27"; s.connection.tcpPortInput = "5567"
        s.deviceQueue.suspend()
        s.runDiagnostics()
        s.ipInput = "192.0.2.99"; s.connection.tcpPortInput = "5555"
        s.deviceQueue.resume()
        await s.waitForPendingWork()
        XCTAssertEqual(f.probes, ["ping 192.0.2.27", "tcp 192.0.2.27:5567 2.0"])
        XCTAssertEqual(f.requests.map(\.arguments), [["-s", "192.0.2.27:5567", "get-state"]])
        XCTAssertEqual(f.requests.map(\.serverPort), ["5038"])
        XCTAssertTrue(s.logLines.contains { $0.contains("TCP 192.0.2.27:5567") })
    }

    func testDiagnosticsDoesNotMixUSBOrDifferentTCPWithEnteredAddress() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.ipInput = "192.0.2.27"
            s.connection.tcpPortInput = "5555" // Same host, different port is also a different target.
            s.runDiagnostics(); await s.waitForPendingWork()
            XCTAssertEqual(f.probes, ["ping 192.0.2.27", "tcp 192.0.2.27:5555 2.0"])
            XCTAssertTrue(f.requests.isEmpty)
            XCTAssertFalse(s.logLines.contains { $0.contains("adb 设备状态:") })
            XCTAssertTrue(s.logLines.contains { $0.contains("填写的 TCP 地址") })
        }
    }

    func testOfflineDiagnosticsRejectsInvalidInputWithoutTargetCommands() async {
        for (host, port) in [("", "5555"), ("192.0.2.27", "0"), ("192.0.2.27", "65536"), ("bad;host", "5567")] {
            let f = RoutingFixture(nil)
            f.state.ipInput = host; f.state.connection.tcpPortInput = port
            f.state.runDiagnostics(); await f.state.waitForPendingWork()
            XCTAssertTrue(f.probes.isEmpty)
            XCTAssertTrue(f.requests.isEmpty)
        }
        let f = RoutingFixture(nil)
        f.state.ipInput = "192.0.2.27"; f.state.connection.tcpPortInput = "5567"
        f.state.runDiagnostics(); await f.state.waitForPendingWork()
        XCTAssertEqual(f.probes, ["ping 192.0.2.27", "tcp 192.0.2.27:5567 2.0"])
        XCTAssertTrue(f.requests.isEmpty)
    }

    func testTerminalShellPinsSubmittedUSBAndTCPAndEscapesScript() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.systemQueue.suspend()
            s.openAdbShell()
            s.adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.99"))
            s.systemQueue.resume()
            await s.waitForPendingWork()
            XCTAssertEqual(f.scripts.count, 1)
            let script = f.scripts.first ?? ""
            XCTAssertTrue(script.contains("adb -s '\(endpoint.serial)' shell"))
            XCTAssertTrue(script.contains("Mimonitor · Shell · \(endpoint.serial)"))
            XCTAssertTrue(script.contains(#"export PATH='/fake/O'\\''Brien \"ADB\"':$PATH; export ANDROID_ADB_SERVER_PORT='5038'"#))
            XCTAssertFalse(script.contains("192.0.2.99"))
            XCTAssertFalse(script.contains("ANDROID_SERIAL"))
            XCTAssertTrue(f.requests.isEmpty)
        }
    }

    func testTerminalShellRejectsMissingOrCancelledSessionButGenericTerminalStaysOffline() async {
        for cancelled in [false, true] {
            let f = RoutingFixture(cancelled ? RoutingFixture.usb : nil), s = f.state
            // A stale connected presentation must not authorize a target command.
            s.connectionStatus = .connected("stale")
            if cancelled { s.adb.cancelSession() }
            s.openAdbShell(); await s.waitForPendingWork()
            XCTAssertTrue(f.scripts.isEmpty)
            s.connectionStatus = .disconnected
            s.openAdbCmd(); await s.waitForPendingWork()
            XCTAssertEqual(f.scripts.count, 1)
            XCTAssertFalse(f.scripts.last?.contains("adb -s") ?? true)
            XCTAssertFalse(f.scripts.last?.contains("ANDROID_SERIAL") ?? true)
            XCTAssertTrue(f.scripts.last?.contains("ANDROID_ADB_SERVER_PORT='5038'") ?? false)
        }
    }
}

@MainActor
final class ControlRoutingTests: XCTestCase {
    private let refresh = "am broadcast -a com.xiaomi.mitv.action.PIC_MODE_CHANGED --ei picmode 7"
    private let volumeRead = "service call audio 22 i32 3"
    private let muteRead = "service call audio 17 i32 3"
    private func volumeWrite(_ value: Int) -> String {
        "service call audio 12 i32 3 i32 \(value) i32 0 s16 com.android.shell"
    }
    private let muteWrite = "service call audio 10 i32 3 i32 -100 i32 0 s16 com.android.shell"
    // Expected protocol strings, independent of AdbClient's builders.
    private func tv(_ args: String, jar: String = "MtkDirectTool") -> String {
        #"service call TvService 3 s16 "sh -c eval\${IFS}CLASSPATH=/data/data/mitv.service/cache/"#
        + jar + #".jar\${IFS}/system/bin/app_process\${IFS}/data/data/mitv.service/cache\${IFS}"#
        + args.replacingOccurrences(of: " ", with: #"\${IFS}"#) + "\""
    }
    private func assertRoute(_ f: RoutingFixture, _ endpoint: AdbEndpoint,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(f.requests.isEmpty, file: file, line: line)
        for request in f.requests {
            XCTAssertEqual(Array(request.arguments.prefix(2)), ["-s", endpoint.serial], file: file, line: line)
            XCTAssertEqual(request.serverPort, "5038", file: file, line: line)
            XCTAssertEqual(request.executable, RoutingFixture.adbPath, file: file, line: line)
            XCTAssertTrue(["shell", "install", "push", "get-state"].contains(request.arguments[2]), file: file, line: line)
        }
    }
    private func assertShells(_ f: RoutingFixture, _ endpoint: AdbEndpoint, _ commands: [String],
                              file: StaticString = #filePath, line: UInt = #line) {
        assertRoute(f, endpoint, file: file, line: line)
        XCTAssertEqual(f.requests.map(\.arguments), commands.map { ["-s", endpoint.serial, "shell", $0] }, file: file, line: line)
    }
    private func sourceCommands(_ source: Int) -> [String] {
        ["am force-stop com.xiaomi.mitv.tvplayer",
         "am start -a com.xiaomi.mitv.tvplayer.EXTSRC_PLAY -n com.xiaomi.mitv.tvplayer/.ExternalSourceActivity --ei input \(source) -f 0x10000000", refresh]
    }

    func testVolumeMuteAndPollUseUSBOrTCPWithoutChangingResultSemantics() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            XCTAssertEqual(s.dashboardVolumeTransport, "\(endpoint.isUSB ? "USB" : "TCP") ADB · \(endpoint.serial)")
            s.setDashboardVolume(27); await s.waitForPendingWork()
            assertShells(f, endpoint, [volumeWrite(27), volumeRead])
            XCTAssertEqual(s.mediaVolumeHardware, 27); XCTAssertNil(s.dashboardVolumeError)
            f.clear()
            s.toggleDashboardMute(); await s.waitForPendingWork()
            assertShells(f, endpoint, [muteRead, muteWrite])
            XCTAssertEqual(s.dashboardMuted, true)
            f.clear()
            s.refreshMediaVolumeState(); await s.waitForPendingWork()
            assertShells(f, endpoint, [volumeRead, muteRead])
            XCTAssertEqual(s.dashboardVolume, 27); XCTAssertEqual(s.dashboardMuted, true)
            s.stop()
        }
    }

    func testPictureGameSourceLightAndRemoteProductionEntries() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            let cases: [(String, () -> Void, [String])] = [
                ("picture", { s.setPictureSlider(title: "背光", value: 51, jniKey: "g_disp__disp_back_light",
                    settingsKeys: ["picture_backlight", "xiaomi_picture_backlight"]) },
                 [tv("MtkDirectTool set g_disp__disp_back_light 51 3"), refresh,
                  "settings put global picture_backlight 51; settings put global xiaomi_picture_backlight 51"]),
                ("game", { s.setGameFeature(key: "monitor_menu_fps_counter", value: 1, message: "FPS") },
                 ["settings put global monitor_menu_fps_counter 1", refresh]),
                ("source", { s.setSource(30) }, sourceCommands(30)),
                ("light", { s.setLightColor(3) },
                 ["settings put global atmosphere_light_switcher_pm2 2", "settings put global atmosphere_light_illumination 9",
                  "settings put global atmosphere_light_color_temp 1", "settings put global atmosphere_light_color_value 3",
                  tv("ColorfulLedTool solid 9 3", jar: "ColorfulLedTool")]),
                ("remote", { s.key("KEYCODE_DPAD_CENTER") }, ["input keyevent KEYCODE_DPAD_CENTER"])
            ]
            for (_, action, expected) in cases {
                f.clear(); action(); await s.waitForPendingWork()
                assertShells(f, endpoint, expected)
            }
            s.stop()
        }
    }

    func testMenuBarAndHotkeysDelegateToActualControlEntries() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.applyMenuBarOption("response_time", value: 3); await s.waitForPendingWork()
            assertShells(f, endpoint, [tv("MtkDirectTool set g_video__vid_od_response_time 3 3"),
                                     "settings put global picture_response_time 3", refresh])
            f.clear()
            s.applyMenuBarOption("source", value: 24); await s.waitForPendingWork()
            assertShells(f, endpoint, sourceCommands(24))
            f.clear()
            s.handleHotkeyTrigger("input_source_cycle"); await s.waitForPendingWork()
            assertShells(f, endpoint, sourceCommands(29))
            f.clear()
            s.handleHotkeyTrigger("picture_mode_cycle")
            XCTAssertEqual(s.picture.currentValues["picture_mode"], "10")
            await s.waitForPendingWork()
            assertShells(f, endpoint, ["settings put global picture_mode 10"])
            f.clear()
            s.mediaVolumeKeysEnabled = true; s.mediaVolumeOutputGateEnabled = false
            s.mediaVolumeNativeOSD = false; s.mediaVolumeStep = 5
            await s.waitForPendingWork()
            assertShells(f, endpoint, [volumeRead, muteRead]) // Enabling media keys performs the existing initial poll.
            f.clear()
            s.handleHotkeyTrigger(HotkeyManager.mediaVolumeUpID); await s.waitForPendingWork()
            assertShells(f, endpoint, [volumeWrite(15), volumeRead])
            f.clear()
            s.handleHotkeyTrigger(HotkeyManager.mediaMuteID); await s.waitForPendingWork()
            assertShells(f, endpoint, [muteWrite])
            f.clear()
            s.mediaBrightnessNativeOSD = false; s.mediaBrightnessFocusOnly = false; s.mediaBrightnessStep = 5
            s.handleHotkeyTrigger(HotkeyManager.mediaBrightnessUpID); await s.waitForPendingWork()
            let done = "/sdcard/Download/Mimonitor_Toolbox/.mtk_ramp_done"
            assertShells(f, endpoint, ["mkdir -p /sdcard/Download/Mimonitor_Toolbox; rm -f \(done); \(tv("MtkDirectTool ramp g_disp__disp_back_light 50 50 3 0 " + done + " 1")) >/dev/null; i=0; while [ $i -lt 80 ] && [ ! -f \(done) ]; do sleep 0.1; i=$((i+1)); done; settings put global picture_backlight 50; settings put global xiaomi_picture_backlight 50"])
            s.stop()
        }
    }

    func testToolsAPK4KAndGuardianKeepExplicitTargetAndOrder() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.installApk(URL(fileURLWithPath: "/fake/app with spaces.apk")); await s.waitForPendingWork()
            assertRoute(f, endpoint)
            // -d here is the existing install downgrade flag, never the bare device selector.
            XCTAssertEqual(f.requests.map(\.arguments), [["-s", endpoint.serial, "install", "-r", "-d", "/fake/app with spaces.apk"]])
            XCTAssertEqual(f.requests.first?.timeout, 120)
            f.clear()
            s.check4KState(); await s.waitForPendingWork()
            assertShells(f, endpoint, ["wm size", "wm density"])
            f.clear()
            s.toggle4K(true); await s.waitForPendingWork()
            assertShells(f, endpoint, ["wm size 3840x2160", "wm density 640", "reboot"])
            f.clear()
            s.startGuardian(); await s.waitForPendingWork()
            assertShells(f, endpoint, guardianStart + guardianReads)
            f.clear()
            s.checkGuardian(); await s.waitForPendingWork()
            assertShells(f, endpoint, guardianReads)
            s.stop()
        }
    }
    func test4KReadFailureStaysUnknownAndSuccessfulReadRecovers() async {
        for endpoint in RoutingFixture.endpoints {
            for command in ["wm size", "wm density"] {
                for failure in [ProcessResult(output: "error: closed", exitCode: 1),
                                ProcessResult(output: "error: device offline", exitCode: 0),
                                ProcessResult(output: "", exitCode: 0),
                                ProcessResult(output: "Override size: invalid\nOverride density: invalid", exitCode: 0),
                                ProcessResult(standardOutput: "Override size: 3840x2160", exitCode: -1, outcome: .timedOut),
                                ProcessResult(standardOutput: "Override density: 640", exitCode: 0, outcome: .exited, outputTruncated: true)] {
                    var shouldFail = true
                    var hasOverride = true
                    let f = RoutingFixture(endpoint) { request in
                        let shell = request.arguments.last!
                        if shouldFail && shell == command { return failure }
                        if shell == "wm size" {
                            return ProcessResult(output: "Physical size: 1920x1080" + (hasOverride ? "\nOverride size: 3840x2160" : ""), exitCode: 0)
                        }
                        if shell == "wm density" {
                            return ProcessResult(output: "Physical density: 320" + (hasOverride ? "\nOverride density: 640" : ""), exitCode: 0)
                        }
                        return nil
                    }
                    let s = f.state
                    s.check4KState(); await s.waitForPendingWork()
                    XCTAssertNotNil(s.tools.fourKReadFailure)
                    XCTAssertFalse(s.logLines.contains { $0.contains("4K UI 检测:") })

                    shouldFail = false
                    s.check4KState(); await s.waitForPendingWork()
                    XCTAssertTrue(s.is4KUI)
                    XCTAssertNil(s.tools.fourKReadFailure)

                    shouldFail = true
                    let logCount = s.logLines.count
                    s.check4KState(); await s.waitForPendingWork()
                    XCTAssertTrue(s.is4KUI) // A failed read must not overwrite the last successful value.
                    XCTAssertNotNil(s.tools.fourKReadFailure)
                    XCTAssertTrue(s.logLines.dropFirst(logCount).contains { $0.contains("4K UI 读取失败") })
                    XCTAssertFalse(s.logLines.dropFirst(logCount).contains { $0.contains("4K UI 检测:") })

                    shouldFail = false; hasOverride = false
                    f.clear()
                    s.check4KState(); await s.waitForPendingWork()
                    XCTAssertFalse(s.is4KUI)
                    XCTAssertNil(s.tools.fourKReadFailure)
                    assertShells(f, endpoint, ["wm size", "wm density"])
                    s.stop()
                }
            }
        }
    }

    private var guardianStart: [String] {
        ["settings get secure enabled_accessibility_services",
         "settings put secure enabled_accessibility_services '0:\(Guardian.accessibility)'",
         "settings put secure accessibility_enabled 1",
         "am start -n \(Guardian.mainActivity) >/dev/null",
         "am broadcast -a \(Guardian.package).ACTION_KEEP_ALIVE -p \(Guardian.package) >/dev/null"]
    }
    private var guardianReads: [String] {
        ["settings get secure enabled_accessibility_services 2>/dev/null", "pm path \(Guardian.package) 2>/dev/null || true",
         "pidof \(Guardian.package) 2>/dev/null || true", "getprop persist.appcontrol_w_mask 2>/dev/null",
         "settings get global adb_enabled 2>/dev/null", "settings get global adb_wifi_enabled 2>/dev/null",
         "getprop service.adb.tcp.port 2>/dev/null", "getprop persist.adb.tcp.port 2>/dev/null",
         "getprop init.svc.adbd 2>/dev/null", "dumpsys package \(Guardian.package) 2>/dev/null | grep stopped=true | head -n 1"]
    }

    func testGuardianDeploymentPinsInstallConfigurationAndTransportSpecificReconnect() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint) { request in
                request.arguments.contains("install") ? ProcessResult(output: "Success", exitCode: 0) : nil
            }, s = f.state
            s.deployGuardian(); await s.waitForPendingWork()
            let reconnect: [[String]] = endpoint.isUSB ? [["devices", "-l"], ["-s", endpoint.serial, "get-state"],
                ["-s", endpoint.serial, "shell", "echo __mimonitor_probe__"]] : [["-s", endpoint.serial, "get-state"],
                ["-s", endpoint.serial, "shell", "echo __mimonitor_probe__"]]
            let expected = [["-s", endpoint.serial, "install", "-r", "-d", "/fake/guardian.apk"]]
                + (["pm grant \(Guardian.package) android.permission.WRITE_SECURE_SETTINGS 2>/dev/null || true",
                    "cmd deviceidle whitelist +\(Guardian.package) 2>/dev/null || true"] + guardianStart).map { ["-s", endpoint.serial, "shell", $0] }
                + reconnect + guardianReads.map { ["-s", endpoint.serial, "shell", $0] }
            XCTAssertEqual(f.requests.map(\.arguments), expected)
            XCTAssertTrue(f.requests.allSatisfy { $0.serverPort == "5038" && $0.executable == RoutingFixture.adbPath })
            s.stop()
        }
    }

    func testVerifiedInitializationPinsHelperPushesForBothTransports() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint) { request in
                request.arguments.last?.hasPrefix("stat -c") == true ? ProcessResult(output: "0", exitCode: 0) : nil
            }, s = f.state
            f.confirmFixtureIdentity()
            s.initializeVerifiedConnection(); await s.waitForPendingWork()
            assertRoute(f, endpoint)
            let expected: [[String]] = ["MtkDirectTool.jar", "ColorfulLedTool.jar"].flatMap { jar -> [[String]] in
                let copy = #"service call TvService 3 s16 "sh -c eval\${IFS}cp\${IFS}/sdcard/"# + jar
                    + #"\${IFS}/data/data/mitv.service/cache/"# + jar + "\""
                return [["-s", endpoint.serial, "shell", "stat -c %s /sdcard/\(jar) 2>/dev/null || echo 0"],
                 ["-s", endpoint.serial, "push", "/fake/\(jar)", "/sdcard/\(jar)"],
                 ["-s", endpoint.serial, "shell", copy]]
            }
            XCTAssertEqual(Array(f.requests.prefix(6)).map(\.arguments), expected)
            XCTAssertEqual(f.requests.filter { $0.arguments.contains("push") }.map(\.timeout), [30, 30])
            s.stop()
        }
    }

    func testUnknownIdentityAllowsManualControlsButNotPresetsOrMemory() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(nil) { request in
                ["getprop ro.serialno", "getprop ro.boot.serialno"].contains(request.arguments.last ?? "")
                    ? ProcessResult(output: "unknown", exitCode: 0) : nil
            }, s = f.state
            if endpoint.isUSB { s.connectUSB(serial: endpoint.serial) }
            else { s.ipInput = endpoint.tcpHost; s.connection.tcpPortInput = "5567"; s.connect() }
            await s.waitForPendingWork()
            XCTAssertTrue(s.isConnected); XCTAssertTrue(s.connection.identityRestricted)
            XCTAssertNil(s.connection.identityEvidence)
            f.clear()
            s.setDashboardVolume(27); s.key("KEYCODE_DPAD_CENTER"); s.openAdbShell()
            await s.waitForPendingWork()
            assertShells(f, endpoint, [volumeWrite(27), volumeRead, "input keyevent KEYCODE_DPAD_CENTER"])
            XCTAssertEqual(f.scripts.count, 1)
            f.clear()
            s.createPreset(name: "blocked"); s.initializeVerifiedConnection()
            await s.waitForPendingWork()
            XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(s.presetConfiguration.presets.isEmpty)
            XCTAssertTrue(s.memoriesSuspendedByPreset)
            // Local configuration remains editable without device ownership.
            s.setPresetMenuBarVisibility(id: PicturePreset.baselineID, visible: true); await s.waitForPendingWork()
            XCTAssertEqual(s.presetConfiguration.menuBarPresetIDs, [PicturePreset.baselineID])
            XCTAssertTrue(f.requests.isEmpty)
            s.stop()
        }
    }

    func testConflictAndMissingSessionCannotDispatchControlsOrShell() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.resolveConnectionIdentity(.conflict("fixture conflict"), snapshot: s.presetWorker.connectionProfileSnapshot(), endpoint: endpoint)
            await s.waitForPendingWork(); f.clear()
            XCTAssertTrue(s.connection.identityConflict); XCTAssertFalse(s.isConnected)
            XCTAssertNil(s.adb.session().endpoint)
            s.setDashboardVolume(27); s.toggleDashboardMute(); s.setSource(30)
            s.applyMenuBarOption("response_time", value: 3); s.handleHotkeyTrigger("picture_mode_cycle")
            s.installApk(URL(fileURLWithPath: "/fake/a.apk")); s.startGuardian(); s.openAdbShell()
            await s.waitForPendingWork()
            XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.scripts.isEmpty)
            s.stop()
        }
        let f = RoutingFixture(nil), s = f.state
        s.connectionStatus = .connected("stale UI")
        s.setDashboardVolume(27); s.toggleDashboardMute(); s.installApk(URL(fileURLWithPath: "/fake/a.apk"))
        s.openAdbShell(); await s.waitForPendingWork()
        XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.scripts.isEmpty)
    }

    func testQueuedControlsAndDiagnosticsAreCancelledRatherThanRedirected() async {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            s.ipInput = "192.0.2.27"; s.connection.tcpPortInput = "5567"
            s.deviceQueue.suspend()
            s.setDashboardVolume(27); s.toggleDashboardMute(); s.setSource(30)
            s.runDiagnostics(); s.installApk(URL(fileURLWithPath: "/fake/a.apk"))
            f.confirmFixtureIdentity(); s.createPreset(name: "cancelled")
            // Same TCP host/different port or a second USB serial still cancels the queued session.
            s.adb.beginSession(endpoint: AdbEndpoint.tcp(host: "192.0.2.27", port: 5577))
            s.seedSimulationReadings(volume: 70, muted: false)
            s.deviceQueue.resume(); await s.waitForPendingWork()
            XCTAssertTrue(f.requests.isEmpty); XCTAssertTrue(f.probes.isEmpty)
            XCTAssertEqual(s.dashboardVolume, 70); XCTAssertEqual(s.dashboardMuted, false)
            XCTAssertTrue(s.presetConfiguration.presets.isEmpty)
            XCTAssertFalse(s.isPresetOperationInFlight)
            s.stop()
        }
    }

    private var presetCapture: [String] {
        let keys = "g_disp__disp_back_light g_video__vid_gamut_mapping_mode g_video__clr_temp g_video__vid_local_dimming g_video__light_sensor_switch g_video__vid_od_response_time g_video__vid_insert_black g_video__dp_adaptive_sync"
        let result = "/sdcard/Download/Mimonitor_Toolbox/.mtk_batch_result.txt"
        return ["settings list global", "settings get global mitv.tvplayer.hdmi.last.source",
                "mkdir -p /sdcard/Download/Mimonitor_Toolbox; rm -f \(result); \(tv("MtkDirectTool batchGet " + keys)) >/dev/null; i=0; while [ $i -lt 30 ] && [ ! -f \(result) ]; do sleep 0.1; i=$((i+1)); done; cat \(result) 2>/dev/null"]
    }

    private var presetWrites: [String] {
        [tv("MtkDirectTool set g_video__dp_adaptive_sync 0 3"), refresh,
         "settings put global picture_mode 14",
         tv("MtkDirectTool set g_video__light_sensor_switch 0 1"), "settings put global tv_picture_light_sensor 0",
         tv("MtkDirectTool set g_disp__disp_back_light 45 3"), refresh,
         "settings put global picture_backlight 45", "settings put global xiaomi_picture_backlight 45",
         "settings put global picture_brightness 50", "settings put global picture_contrast 60",
         "settings put global picture_saturation 50", "settings put global picture_hue 50", "settings put global picture_sharpness 30",
         tv("MtkDirectTool set g_video__clr_temp 2 3"), "settings put global picture_color_temperature 1", refresh,
         tv("MtkDirectTool set g_video__vid_local_dimming 3 3"), "settings put global picture_local_dimming 3",
         "settings put global tv_picture_video_local_dimming 3", refresh,
         tv("MtkDirectTool set g_video__vid_insert_black 0 3"), "settings put global picture_dynamic_definition 0", refresh,
         tv("MtkDirectTool set g_video__vid_od_response_time 2 3"), "settings put global picture_response_time 2", refresh,
         tv("MtkDirectTool set g_video__vid_gamut_mapping_mode 6 3"), "settings put global tv_picture_advanced_video_color_space 6",
         "settings put global tv_picture_video_color_space 6", refresh]
    }

    func testPresetAndBaselineUseProductionAdapterAndOpaqueOwnershipKey() async throws {
        for endpoint in RoutingFixture.endpoints {
            let f = RoutingFixture(endpoint), s = f.state
            f.confirmFixtureIdentity()
            s.createPreset(name: "routing"); await s.waitForPendingWork()
            assertShells(f, endpoint, presetCapture)
            let id = try XCTUnwrap(s.presetConfiguration.presets.first?.id)
            XCTAssertEqual(s.presetConfiguration.baseline?.deviceIdentity, RoutingFixture.owner)
            XCTAssertEqual(s.presetConfiguration.activeDeviceIdentity, RoutingFixture.owner)
            XCTAssertNil(s.presetError)
            f.clear()
            s.applyPreset(id: id); await s.waitForPendingWork()
            assertPresetApplication(f, endpoint)
            XCTAssertFalse(s.presetConfiguration.applicationIncomplete)
            XCTAssertEqual(s.activePresetID, id)
            f.clear()
            s.restoreBaseline(); await s.waitForPendingWork()
            assertPresetApplication(f, endpoint)
            XCTAssertNil(s.activePresetID)
            XCTAssertFalse(s.presetConfiguration.applicationIncomplete)
            XCTAssertNil(s.presetError)
            s.stop()
        }
    }

    private func assertPresetApplication(_ f: RoutingFixture, _ endpoint: AdbEndpoint,
                                         file: StaticString = #filePath, line: UInt = #line) {
        assertRoute(f, endpoint, file: file, line: line)
        let transaction = ["settings get global mitv.tvplayer.hdmi.last.source"] + presetWrites + presetCapture
        XCTAssertEqual(Array(f.requests.prefix(transaction.count)).map(\.arguments),
            transaction.map { ["-s", endpoint.serial, "shell", $0] }, file: file, line: line)
        // Subsequent page refresh reads remain routed to the same endpoint, and introduce no extra writes.
        let writes = f.requests.map { $0.arguments.last ?? "" }.filter {
            $0.hasPrefix("settings put") || $0.contains(#"MtkDirectTool\${IFS}set"#) || $0 == refresh
        }
        XCTAssertEqual(writes, presetWrites, file: file, line: line)
        XCTAssertFalse(f.requests.contains { $0.arguments.contains(RoutingFixture.owner) }, file: file, line: line)
    }
}
