import XCTest
import ToolboxConcurrency
import ToolboxDomain
@testable import ToolboxApplication
@testable import ToolboxPreviewSupport

@MainActor
final class GuardianConfigurationTests: XCTestCase {
    private let read = "settings get secure enabled_accessibility_services"

    private func fixture(_ execute: @escaping (CommandRequest) -> ProcessResult) -> AppCoordinator {
        let base = PreviewRuntime().environment()
        let adb = AdbClient(resources: base.adb.resources, execute: execute)
        let state = AppCoordinator(environment: AppEnvironment(mode: .simulation, preferences: base.preferences,
            adb: adb, hotkeys: base.hotkeys, feedback: base.feedback, scheduler: base.scheduler,
            system: base.system, now: base.now, presetDevice: base.presetDevice))
        adb.ip = "192.0.2.1"
        state.connectionStatus = .connected("fake")
        return state
    }

    func testFailedReadNeverWritesEvenWithEmptyOrPlausiblePartialOutput() {
        for failure in [ProcessResult(output: "", exitCode: 1),
                        ProcessResult(output: "error: device offline", exitCode: 0),
                        ProcessResult(standardOutput: "old.pkg/.Service", exitCode: -1, outcome: .timedOut),
                        ProcessResult(standardOutput: "old.pkg/.Service", exitCode: 0, outcome: .exited, outputTruncated: true)] {
            var commands: [String] = []
            let state = fixture { request in
                commands.append(request.arguments.last!)
                return failure
            }
            XCTAssertThrowsError(try state.enableGuardianAccessibility()) { error in
                XCTAssertTrue(error.localizedDescription.contains("读取 enabled_accessibility_services失败"))
            }
            XCTAssertEqual(commands, [read])
        }
    }

    func testMergePreservesExistingServicesAndAddsGuardianOnlyOnce() throws {
        let guardian = Guardian.accessibility
        for current in ["", "null", "old.pkg/.First:other.pkg/other.pkg.Second",
                        "old.pkg/.First:\(guardian):other.pkg/.Second"] {
            var commands: [String] = []
            let state = fixture { request in
                commands.append(request.arguments.last!)
                return ProcessResult(output: commands.count == 1 ? current : "", exitCode: 0)
            }
            try state.enableGuardianAccessibility()
            let expected = current.isEmpty || current == "null" ? guardian
                : current.contains(guardian) ? current : "\(current):\(guardian)"
            XCTAssertEqual(commands, [read,
                "settings put secure enabled_accessibility_services \(TerminalExecution.shellQuote(expected))",
                "settings put secure accessibility_enabled 1"])
        }
    }

    func testWriteFailurePropagatesItsStepAndStopsRemainingWrites() {
        for failedWrite in ["enabled_accessibility_services", "accessibility_enabled"] {
            var commands: [String] = []
            let state = fixture { request in
                let command = request.arguments.last!
                commands.append(command)
                if command.hasPrefix("settings put secure \(failedWrite) ") {
                    return ProcessResult(output: "permission denied: test failure", exitCode: 1)
                }
                return ProcessResult(output: command == self.read ? "old.pkg/.Service" : "", exitCode: 0)
            }
            XCTAssertThrowsError(try state.enableGuardianAccessibility()) { error in
                XCTAssertTrue(error.localizedDescription.contains("写入 \(failedWrite)失败"))
                XCTAssertTrue(error.localizedDescription.contains("permission denied: test failure"))
            }
            XCTAssertEqual(commands.count, failedWrite == "enabled_accessibility_services" ? 2 : 3)
        }
    }

    func testDeployAndStartStopBeforeLaunchingWhenConfigurationFails() async {
        for deploy in [false, true] {
            for failedStep in [read, "settings put secure enabled_accessibility_services", "settings put secure accessibility_enabled"] {
                var commands: [String] = []
                let state = fixture { request in
                    let command = request.arguments.last!
                    commands.append(command)
                    if request.arguments.contains("install") { return ProcessResult(output: "Success", exitCode: 0) }
                    if command.hasPrefix(failedStep) { return ProcessResult(output: "permission denied: caller test", exitCode: 1) }
                    return ProcessResult(output: "", exitCode: 0)
                }
                if deploy { state.deployGuardian() } else { state.startGuardian() }
                await state.waitForPendingWork()
                XCTAssertEqual(state.guardianStatus, "状态：配置失败")
                XCTAssertFalse(commands.contains { $0.hasPrefix("am start") || $0.hasPrefix("am broadcast") })
                XCTAssertTrue(state.logLines.contains { $0.contains("permission denied: caller test") })
            }
        }
    }

    func testGuardianTransportFailurePublishesUnknownInsteadOfDeviceFaults() async {
        for failure in [ProcessResult(output: "error: closed", exitCode: 1),
                        ProcessResult(output: "", exitCode: 1),
                        ProcessResult(output: "error: device offline", exitCode: 0),
                        ProcessResult(standardOutput: "package:/partial", exitCode: -1, outcome: .timedOut),
                        ProcessResult(standardOutput: "package:/partial", exitCode: 0, outcome: .exited, outputTruncated: true)] {
            let state = fixture { _ in failure }
            state.checkGuardian(); await state.waitForPendingWork()
            XCTAssertTrue(state.guardianStatus.contains("未知"), state.guardianStatus)
            XCTAssertFalse(state.guardianStatus.contains("未安装"))
            XCTAssertFalse(state.guardianStatus.contains("被停止"))
            XCTAssertTrue(state.logLines.contains { $0.contains("读取失败") })
            state.stop()
        }
    }

    func testSuccessfulAbsentGuardianReadStillReportsDeviceState() async {
        let state = fixture { _ in ProcessResult(output: "", exitCode: 0) }
        state.checkGuardian(); await state.waitForPendingWork()
        XCTAssertTrue(state.guardianStatus.contains("未安装"))
        XCTAssertFalse(state.guardianStatus.contains("未知"))
        state.stop()
    }
}
