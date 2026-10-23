import Foundation
import XCTest
import ToolboxConcurrency
import ToolboxDomain
import MimonitorPresetCore
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

private final class ManualConnectionTrace {
    private let lock = NSLock()
    private var commands: [[String]] = []
    private var presetDevices = 0
    func record(_ request: CommandRequest) {
        lock.lock(); defer { lock.unlock() }
        commands.append(request.arguments)
    }
    func recordPresetDevice() {
        lock.lock(); defer { lock.unlock() }
        presetDevices += 1
    }
    var arguments: [[String]] { lock.lock(); defer { lock.unlock() }; return commands }
    var presetDeviceCount: Int { lock.lock(); defer { lock.unlock() }; return presetDevices }
}

@MainActor final class ManualConnectionTests: XCTestCase {
    private let usbSerial = "000ManualUSB"
    private let readyCommands = [
        ["devices", "-l"],
        ["-s", "000ManualUSB", "get-state"],
        ["-s", "000ManualUSB", "shell", "echo __mimonitor_probe__"]
    ]

    private let identityCommands = [
        ["-s", "000ManualUSB", "shell", "getprop ro.serialno"],
        ["-s", "000ManualUSB", "shell", "getprop ro.boot.serialno"]
    ]

    private func fixture(_ runtime: PreviewRuntime = PreviewRuntime(),
                         respond: ((CommandRequest) -> ProcessResult)? = nil)
        -> (AppCoordinator, PreviewRuntime, ManualConnectionTrace) {
        let base = runtime.environment(), trace = ManualConnectionTrace()
        let adb = AdbClient(resources: base.adb.resources) { request in
            trace.record(request)
            return respond?(request) ?? runtime.display.execute(request)
        }
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation,
            preferences: base.preferences, adb: adb, hotkeys: base.hotkeys, feedback: base.feedback,
            scheduler: base.scheduler, system: base.system, now: base.now, calendar: base.calendar,
            presetDevice: { client, endpoint, identity in
                trace.recordPresetDevice()
                return base.presetDevice(client, endpoint, identity)
            }))
        return (state, runtime, trace)
    }

    private func configureUSB(_ runtime: PreviewRuntime, state: String = "device") {
        runtime.display.configureDiscovery(rows: "\(usbSerial) \(state) usb:fixture-1 model:MiTV_Fixture")
    }

    func testDiscoveryPublishesCandidatesWithoutChangingActiveSessionOrSelection() async {
        let (state, runtime, trace) = fixture()
        configureUSB(runtime)
        state.adb.beginSession(ip: "192.0.2.80")
        state.connection.activeEndpoint = state.adb.endpoint
        state.connection.selectedEndpoint = state.adb.endpoint
        state.connection.selectedUSBSerial = "000PreviousChoice"
        state.ipInput = "192.0.2.80"
        state.connectionStatus = .connected("existing TCP")
        let session = state.adb.session(), intent = state.connectionIntent.generation

        state.refreshDevices()
        XCTAssertEqual(state.connection.discoveryStatus, .discovering)
        XCTAssertEqual(state.connectionStatus, .connected("existing TCP"))
        await state.waitForPendingWork()

        XCTAssertEqual(trace.arguments, [["devices", "-l"]])
        XCTAssertEqual(state.connection.discoveredDevices.map(\.serial), [usbSerial])
        XCTAssertEqual(state.connection.discoveryStatus, .idle)
        XCTAssertEqual(state.adb.endpoint, session.endpoint)
        XCTAssertTrue(state.adb.session().cancellation === session.cancellation)
        XCTAssertFalse(session.cancellation.isCancelled)
        XCTAssertEqual(state.connection.activeEndpoint, session.endpoint)
        XCTAssertEqual(state.connection.selectedEndpoint, session.endpoint)
        XCTAssertEqual(state.connection.selectedUSBSerial, "000PreviousChoice")
        XCTAssertEqual(state.connection.mode, .tcp)
        XCTAssertEqual(state.connectionIntent.generation, intent)
        XCTAssertEqual(state.connectionStatus, .connected("existing TCP"))
        state.stop()
    }

    func testEmptyOrFailedDiscoveryDoesNotDisconnectAnActiveSession() async {
        for result in [ProcessResult(output: "List of devices attached\n\n", exitCode: 0),
                       ProcessResult(output: "List of devices attached\n", exitCode: 1)] {
            let (state, _, trace) = fixture(respond: { _ in result })
            state.adb.beginSession(ip: "192.0.2.80")
            state.connection.activeEndpoint = state.adb.endpoint
            state.connection.selectedEndpoint = state.adb.endpoint
            state.connectionStatus = .connected("existing TCP")
            let session = state.adb.session()

            state.refreshDevices()
            await state.waitForPendingWork()

            XCTAssertEqual(trace.arguments, [["devices", "-l"]])
            XCTAssertEqual(state.connectionStatus, .connected("existing TCP"))
            XCTAssertEqual(state.connection.activeEndpoint, session.endpoint)
            XCTAssertEqual(state.connection.selectedEndpoint, session.endpoint)
            XCTAssertTrue(state.adb.session().cancellation === session.cancellation)
            XCTAssertFalse(session.cancellation.isCancelled)
            XCTAssertTrue(state.connection.discoveredDevices.isEmpty)
            XCTAssertEqual(state.connection.discoveryStatus, result.succeeded ? .idle : .failed(.commandFailed(1)))
            if result.succeeded {
                XCTAssertEqual(state.connection.discoverySnapshot?.outcome, .complete([]))
            } else {
                XCTAssertEqual(state.connection.discoverySnapshot?.outcome, .failed(.commandFailed(1)))
            }
            state.stop()
        }
    }

    func testUSBReadyOnlyValidatesChannelAndPreservesLegacyTCPPreference() async {
        let runtime = PreviewRuntime()
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        let (state, _, trace) = fixture(runtime)
        configureUSB(runtime)
        state.connectUSB(serial: usbSerial)
        await state.waitForPendingWork()

        XCTAssertEqual(trace.arguments, readyCommands + identityCommands)
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.connection.mode, .usb)
        XCTAssertEqual(state.connection.selectedUSBSerial, usbSerial)
        XCTAssertEqual(state.connection.selectedEndpoint, state.adb.endpoint)
        XCTAssertEqual(state.connection.activeEndpoint, state.adb.endpoint)
        XCTAssertEqual(state.adb.serial, usbSerial)
        XCTAssertTrue(state.connection.identityRestricted)
        XCTAssertFalse(state.connection.identityNotice.isEmpty)
        XCTAssertTrue(state.loadedPages.isEmpty)
        XCTAssertTrue(state.currentValues.isEmpty)
        XCTAssertEqual(trace.presetDeviceCount, 0)
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
        XCTAssertNil(runtime.preferences.data(forKey: "picture_presets_v1"))
        state.stop()
    }

    func testUnknownCandidateRequiresExplicitTargetedTypeValidationBeforeReady() async {
        let (state, runtime, trace) = fixture()
        runtime.display.configureDiscovery(rows: "\(usbSerial) device model:MiTV_Fixture",
                                           devicePaths: [usbSerial: "usb:fixture-1"])
        state.connection.selectedUSBSerial = usbSerial
        state.setConnectionMode(.usb)
        XCTAssertTrue(trace.arguments.isEmpty)
        state.connect()
        await state.waitForPendingWork()

        XCTAssertEqual(trace.arguments, [["devices", "-l"], ["-s", usbSerial, "get-devpath"],
            ["-s", usbSerial, "get-state"], ["-s", usbSerial, "shell", "echo __mimonitor_probe__"]] + identityCommands)
        XCTAssertEqual(state.connection.activeEndpoint?.serial, usbSerial)
        XCTAssertTrue(state.isConnected)
        state.stop()
    }

    func testRestrictedUSBBlocksDueTasksPresetsAndMemoryMutations() async throws {
        let runtime = PreviewRuntime()
        let memory = Data("{ \"sdr\": 3, \"hdr\": 2 }".utf8)
        runtime.preferences.set(memory, forKey: "local_dimming_memory")
        runtime.preferences.set(true, forKey: "hdr_sdr_local_dimming_enabled")
        runtime.preferences.set(true, forKey: "freesync_mode_memory_enabled")
        runtime.preferences.set(true, forKey: "crosshair_game_mode_only")
        var configuration = PresetConfiguration()
        configuration.presets = [PicturePreset(id: "scheduled", name: "Scheduled", values: ["picture_backlight": "77"])]
        let clock = runtime.environment()
        let parts = clock.calendar.dateComponents([.hour, .minute], from: clock.now())
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0), end = (minute + 1) % 1440
        configuration.tasks = [ScheduledPresetTask(id: "due", presetID: "scheduled",
            start: String(format: "%02d:%02d", minute / 60, minute % 60),
            end: String(format: "%02d:%02d", end / 60, end % 60))]
        let encoded = try JSONEncoder().encode(configuration)
        runtime.preferences.set(encoded, forKey: "picture_presets_v1")
        let (state, _, trace) = fixture(runtime)
        configureUSB(runtime)
        state.presetConfiguration = configuration
        XCTAssertNotNil(PresetSchedule.activeTask(configuration.tasks, minute: state.currentMinute()))

        state.connectUSB(serial: usbSerial)
        await state.waitForPendingWork()
        state.currentValues = ["picture_mode": "14", "front_sight_index": "5"]
        state.checkAutomaticTasks()
        state.createPreset(name: "Must not capture")
        state.applyPreset(id: "scheduled")
        state.applyHdrMemory(state: false)
        state.reconcileCrosshairModeState()
        state.toggleHdrMemory(false)
        state.toggleFreesyncMemory(false)
        state.toggleCrosshairGameModeOnly(false)
        await state.waitForPendingWork()

        XCTAssertEqual(trace.arguments, readyCommands + identityCommands)
        XCTAssertEqual(trace.presetDeviceCount, 0)
        XCTAssertTrue(state.memoriesSuspendedByPreset)
        XCTAssertFalse(state.effectiveHdrMemoryEnabled)
        XCTAssertFalse(state.effectiveFreesyncMemoryEnabled)
        XCTAssertFalse(state.isPresetOperationInFlight)
        XCTAssertTrue(state.hdrMemoryEnabled)
        XCTAssertTrue(state.freesyncMemoryEnabled)
        XCTAssertTrue(state.crosshairGameModeOnly)
        XCTAssertEqual(runtime.preferences.data(forKey: "picture_presets_v1"), encoded)
        XCTAssertEqual(runtime.preferences.data(forKey: "local_dimming_memory"), memory)
        XCTAssertTrue(runtime.preferences.bool(forKey: "hdr_sdr_local_dimming_enabled"))
        XCTAssertTrue(runtime.preferences.bool(forKey: "freesync_mode_memory_enabled"))
        XCTAssertTrue(runtime.preferences.bool(forKey: "crosshair_game_mode_only"))
        XCTAssertNil(runtime.preferences.object(forKey: "crosshair_memory"))
        XCTAssertFalse(runtime.display.recordedCommands.contains("preset.apply"))
        state.stop()
    }

    func testUnauthorizedOfflineAndFailedUSBDoNotFallBackToSavedTCP() async {
        for scenario in ["unauthorized", "offline", "probe-failure"] {
            let runtime = PreviewRuntime()
            runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
            configureUSB(runtime, state: scenario == "probe-failure" ? "device" : scenario)
            let (state, _, trace) = fixture(runtime) { request in
                if scenario == "probe-failure", request.arguments.last == "echo __mimonitor_probe__" {
                    return ProcessResult(output: "__mimonitor_probe__", exitCode: 1)
                }
                return runtime.display.execute(request)
            }
            state.connectUSB(serial: usbSerial)
            await state.waitForPendingWork()
            let expected = scenario == "probe-failure" ? readyCommands : [["devices", "-l"]]
            XCTAssertEqual(trace.arguments, expected)
            switch scenario {
            case "unauthorized": XCTAssertEqual(state.connectionStatus, .awaitingAuthorization)
            case "offline": XCTAssertEqual(state.connectionStatus, .offline(usbSerial))
            default:
                guard case .failed = state.connectionStatus else { XCTFail("Probe failure must be visible"); state.stop(); continue }
            }
            state.monitorAdbServer(refreshState: true)
            state.autoConnectOnStartup()
            state.recoverAfterWake()
            runtime.scheduler.advance(by: 60)
            await state.waitForPendingWork()

            XCTAssertEqual(trace.arguments, expected)
            XCTAssertFalse(state.isConnected)
            XCTAssertNil(state.adb.endpoint)
            XCTAssertNil(state.connection.activeEndpoint)
            XCTAssertEqual(state.connection.mode, .usb)
            XCTAssertTrue(state.connection.identityRestricted)
            XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
            state.stop()
        }
    }

    func testDisconnectOrModeChangeDiscardsLateSuccessfulUSBProbe() async {
        for changeMode in [false, true] {
            let runtime = PreviewRuntime(), began = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            configureUSB(runtime)
            let (state, _, trace) = fixture(runtime) { request in
                if request.arguments.last == "echo __mimonitor_probe__" {
                    began.signal()
                    _ = release.wait(timeout: .now() + 3)
                    // Deliberately return success even after cancellation; the coordinator must reject it.
                    return ProcessResult(output: "__mimonitor_probe__", exitCode: 0)
                }
                return runtime.display.execute(request)
            }
            state.connectUSB(serial: usbSerial)
            XCTAssertEqual(began.wait(timeout: .now() + 3), .success)
            let old = state.adb.session()
            if changeMode { state.setConnectionMode(.tcp) } else { state.disconnectAdb() }
            release.signal()
            await state.waitForPendingWork()

            XCTAssertEqual(trace.arguments, readyCommands)
            XCTAssertTrue(old.cancellation.isCancelled)
            XCTAssertEqual(state.connectionStatus, .disconnected)
            XCTAssertNil(state.adb.endpoint)
            XCTAssertNil(state.connection.activeEndpoint)
            XCTAssertNil(state.connection.selectedEndpoint)
            XCTAssertEqual(state.connection.mode, changeMode ? .tcp : .usb)
            XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
            state.stop()
        }
    }

    func testValidTCPPortsUseEnteredTargetWithoutImplicitPreferenceWrite() async {
        for (host, port) in [("192.0.2.50", "1"), ("Monitor.Example", "5555"), ("192.0.2.51", "65535")] {
            let runtime = PreviewRuntime()
            runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
            let (state, _, trace) = fixture(runtime, respond: { _ in
                ProcessResult(output: "error: device unauthorized", exitCode: 1)
            })
            state.ipInput = host
            state.connection.tcpPortInput = port
            state.connect()
            await state.waitForPendingWork()

            XCTAssertEqual(trace.arguments, [["-s", "\(host):\(port)", "get-state"]])
            XCTAssertEqual(state.connection.selectedEndpoint?.serial, "\(host):\(port)")
            XCTAssertEqual(state.adb.serial, "\(host):\(port)")
            XCTAssertEqual(state.connectionStatus, .awaitingAuthorization)
            XCTAssertNil(state.connection.activeEndpoint)
            XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
            state.stop()
        }
    }

    func testInvalidTCPInputPreservesCurrentSessionAndPreferenceWithoutDispatch() async {
        let runtime = PreviewRuntime()
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        let (state, _, trace) = fixture(runtime)
        state.adb.beginSession(ip: "192.0.2.80")
        state.connection.activeEndpoint = state.adb.endpoint
        state.connection.selectedEndpoint = state.adb.endpoint
        state.connectionStatus = .connected("existing TCP")
        let old = state.adb.session(), intent = state.connectionIntent.generation
        for (host, port) in [("192.0.2.50", ""), ("192.0.2.50", "0"), ("192.0.2.50", "65536"),
                             ("192.0.2.50", "-1"), ("192.0.2.50", "55x"), ("192.0.2.50", " 5555"),
                             ("", "5555"), ("999.0.0.1", "5555"), ("https://host", "5555"),
                             ("[::1]", "5555"), ("host;id", "5555")] {
            state.ipInput = host
            state.connection.tcpPortInput = port
            state.connect()
        }
        await state.waitForPendingWork()

        XCTAssertTrue(trace.arguments.isEmpty)
        XCTAssertTrue(state.adb.session().cancellation === old.cancellation)
        XCTAssertFalse(old.cancellation.isCancelled)
        XCTAssertEqual(state.adb.endpoint, old.endpoint)
        XCTAssertEqual(state.connection.activeEndpoint, old.endpoint)
        XCTAssertEqual(state.connection.selectedEndpoint, old.endpoint)
        XCTAssertEqual(state.connectionStatus, .connected("existing TCP"))
        XCTAssertEqual(state.connectionIntent.generation, intent)
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
        state.stop()
    }

    func testModeChangesNeverConnectAndKeepManualRecoverySuppressed() async {
        let runtime = PreviewRuntime()
        runtime.preferences.set("192.0.2.99", forKey: "saved_ip")
        let (state, _, trace) = fixture(runtime)
        configureUSB(runtime)
        state.connection.selectedUSBSerial = usbSerial
        for mode in [ManualConnectionMode.usb, .tcp, .usb] {
            state.setConnectionMode(mode)
            state.autoConnectOnStartup()
            state.monitorAdbServer(refreshState: true)
            state.recoverAfterWake()
            runtime.scheduler.advance(by: 60)
            await state.waitForPendingWork()
            XCTAssertEqual(state.connection.mode, mode)
            XCTAssertEqual(state.connectionStatus, .disconnected)
            XCTAssertNil(state.adb.endpoint)
            XCTAssertNil(state.connection.activeEndpoint)
            XCTAssertFalse(state.connectionIntent.allowsAutomaticRecovery)
            XCTAssertFalse(state.connectionIntent.allowsStartupAttempt)
        }
        XCTAssertTrue(trace.arguments.isEmpty)
        XCTAssertEqual(runtime.preferences.string(forKey: "saved_ip"), "192.0.2.99")
        state.stop()
    }

    func testStopDiscardsLateDiscoveryAndCoalescesDuplicateRefreshRequests() async {
        let began = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let (state, _, trace) = fixture(respond: { _ in
            began.signal()
            _ = release.wait(timeout: .now() + 3)
            return ProcessResult(output: "List of devices attached\n000LateUSB device usb:late\n\n", exitCode: 0)
        })
        let old = AdbDiscoverySnapshot(outcome: .complete([]))
        state.connection.discoverySnapshot = old
        state.refreshDevices()
        XCTAssertEqual(began.wait(timeout: .now() + 3), .success)
        state.refreshDevices()
        state.stop()
        release.signal()
        await state.waitForPendingWork()

        XCTAssertEqual(trace.arguments, [["devices", "-l"]])
        XCTAssertEqual(state.connection.discoverySnapshot, old)
        XCTAssertEqual(state.connection.discoveryStatus, .idle)
        XCTAssertNil(state.adb.endpoint)
        XCTAssertFalse(state.isConnected)
    }
}
