import XCTest
import Foundation
import ToolboxDomain
import ToolboxConcurrency
@testable import ToolboxApplication
@testable import ToolboxMacAdapters
@testable import ToolboxPreviewSupport

private final class LoginFixture {
    enum Failure: Error { case expected }
    var status: LoginItemStatus = .notRegistered
    var nextStatus: LoginItemStatus = .enabled
    var old: LegacyLoginItemRecord?
    var events: [String] = []
    var failBackup = false, failRegister = false, failUnregister = false, failRetire = false
    var failAfterRetire = false, failRestore = false
    var onRegister: (() -> Void)?
    func workflow() -> LoginItemWorkflow {
        LoginItemWorkflow(ports: LoginItemPorts(status: { self.status }, register: {
            self.events.append("register"); if self.failRegister { throw Failure.expected }
            self.status = self.nextStatus; self.onRegister?()
        }, unregister: {
            self.events.append("unregister"); if self.failUnregister { throw Failure.expected }
            self.status = .notRegistered
        }, legacy: { self.old }, backup: { _ in
            self.events.append("backup"); if self.failBackup { throw Failure.expected }
        }, retire: { _ in
            self.events.append("retire"); if self.failRetire { throw Failure.expected }
            self.old = nil; if self.failAfterRetire { throw Failure.expected }
        }, restore: { record in
            self.events.append("restore"); if self.failRestore { throw Failure.expected }; self.old = record
        }))
    }
    func owned(_ status: LegacyLoginItemStatus = .enabled) { old = LegacyLoginItemRecord(bytes: Data("original".utf8), status: status) }
}

final class LoginItemTests: XCTestCase {
    func testConstructionAndReadOnlyStatusMatrixDoNotMutate() {
        for status in LoginItemStatus.allCases {
            let fixture = LoginFixture(); fixture.status = status
            let workflow = fixture.workflow()
            XCTAssertTrue(fixture.events.isEmpty)
            XCTAssertEqual(workflow.snapshot().status, status)
            XCTAssertEqual(workflow.snapshot().enabled, status == .enabled)
            XCTAssertTrue(fixture.events.isEmpty)
        }
    }
    func testMigrationBacksUpThenVerifiesModernBeforeRetiringOld() {
        let fixture = LoginFixture(); fixture.owned()
        let result = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "register", "retire"])
        XCTAssertEqual(result.status, .enabled); XCTAssertEqual(result.legacy, .absent)
        XCTAssertTrue(result.enabled); XCTAssertNil(result.error)
    }
    func testPendingApprovalWithoutOldItemIsNeverShownEnabled() {
        let fixture = LoginFixture(); fixture.nextStatus = .requiresApproval
        let result = fixture.workflow().setEnabled(true, cancellation: CommandCancellation())
        XCTAssertEqual(result.status, .requiresApproval); XCTAssertFalse(result.enabled)
        XCTAssertEqual(fixture.events, ["register"])
    }
    func testPendingApprovalWithOldItemWithdrawsNewRequestAndKeepsOld() {
        let fixture = LoginFixture(); fixture.owned(); fixture.nextStatus = .requiresApproval
        let result = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "register", "unregister"])
        XCTAssertEqual(result.legacy, .enabled); XCTAssertEqual(result.status, .notRegistered)
        XCTAssertNotNil(fixture.old)
    }
    func testSystemDisabledOldOrModernItemIsNotAutomaticallyReenabled() {
        for (modern, old) in [(LoginItemStatus.notRegistered, LegacyLoginItemStatus.disabled), (.requiresApproval, .enabled)] {
            let fixture = LoginFixture(); fixture.status = modern; fixture.owned(old)
            _ = fixture.workflow().reconcile(CommandCancellation())
            XCTAssertTrue(fixture.events.isEmpty)
        }
    }
    func testBackupFailureDoesNotTouchEitherRegistration() {
        let fixture = LoginFixture(); fixture.owned(); fixture.failBackup = true
        let result = fixture.workflow().setEnabled(true, cancellation: CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup"]); XCTAssertEqual(fixture.status, .notRegistered)
        XCTAssertNotNil(result.error); XCTAssertNotNil(fixture.old)
    }
    func testRegisterFailureLeavesOldFileUnchangedAndReportsRealStatus() {
        let fixture = LoginFixture(); fixture.owned(); fixture.failRegister = true
        let result = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "register"])
        XCTAssertEqual(result.status, .notRegistered); XCTAssertEqual(fixture.old?.bytes, Data("original".utf8))
        XCTAssertNotNil(result.error)
    }
    func testRetirementFailureRollsBackNewAndRestoresBackup() {
        let fixture = LoginFixture(); fixture.owned(); fixture.failAfterRetire = true
        let result = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "register", "retire", "unregister", "restore"])
        XCTAssertEqual(result.status, .notRegistered); XCTAssertEqual(result.legacy, .enabled)
        XCTAssertEqual(fixture.old?.bytes, Data("original".utf8)); XCTAssertNotNil(result.error)
    }
    func testFailedRollbackCannotRestoreOldAlongsideStillEnabledModernItem() {
        let fixture = LoginFixture(); fixture.owned(); fixture.failAfterRetire = true; fixture.failUnregister = true
        let result = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(result.status, .enabled); XCTAssertNil(fixture.old)
        XCTAssertFalse(fixture.events.contains("restore")); XCTAssertNotNil(result.error)
    }
    func testPreexistingModernItemIsNotUnregisteredOnLegacyRetirementFailure() {
        let fixture = LoginFixture(); fixture.status = .enabled; fixture.owned(); fixture.failAfterRetire = true
        _ = fixture.workflow().reconcile(CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "retire"])
        XCTAssertEqual(fixture.status, .enabled)
    }
    func testExplicitDisableRemovesModernAndOnlyVerifiedOldFile() {
        let fixture = LoginFixture(); fixture.status = .enabled; fixture.owned()
        let result = fixture.workflow().setEnabled(false, cancellation: CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "unregister", "retire"])
        XCTAssertFalse(result.enabled); XCTAssertNil(fixture.old)
    }
    func testUnregisterFailureDoesNotRetireOldOrPretendDisabled() {
        let fixture = LoginFixture(); fixture.status = .enabled; fixture.owned(); fixture.failUnregister = true
        let result = fixture.workflow().setEnabled(false, cancellation: CommandCancellation())
        XCTAssertEqual(fixture.events, ["backup", "unregister"])
        XCTAssertTrue(result.enabled); XCTAssertNotNil(fixture.old); XCTAssertNotNil(result.error)
    }
    func testUnrecognizedOldItemBlocksAutomaticMutation() {
        let fixture = LoginFixture(); fixture.owned(.unrecognized)
        for enabled in [false, true] {
            XCTAssertNotNil(fixture.workflow().setEnabled(enabled, cancellation: CommandCancellation()).error)
        }
        XCTAssertTrue(fixture.events.isEmpty)
    }
    func testCancellationBeforeStartAndDuringRegistrationKeepOldItemSafe() {
        let fixture = LoginFixture(); fixture.owned()
        let cancelled = CommandCancellation(); cancelled.cancel()
        _ = fixture.workflow().reconcile(cancelled); XCTAssertTrue(fixture.events.isEmpty)
        let token = CommandCancellation(); fixture.onRegister = { token.cancel() }
        _ = fixture.workflow().reconcile(token)
        XCTAssertEqual(fixture.events, ["backup", "register", "unregister"])
        XCTAssertNotNil(fixture.old)
    }
    func testMenuBarLaunchPolicyPreservesManualAndLegacyLaunches() {
        XCTAssertFalse(AppLaunchPolicy.startsInMenuBar(arguments: ["Toolbox"], loginEvent: false))
        XCTAssertTrue(AppLaunchPolicy.startsInMenuBar(arguments: ["Toolbox", "--minimized"], loginEvent: false))
        XCTAssertTrue(AppLaunchPolicy.startsInMenuBar(arguments: ["Toolbox"], loginEvent: true))
    }
}

final class LegacyLoginItemFileTests: XCTestCase {
    private let executable = URL(fileURLWithPath: "/Applications/Toolbox.app/Contents/MacOS/MimonitorToolbox")
    private func data(path: String? = nil, extras: [String: Any] = [:]) throws -> Data {
        var plist: [String: Any] = ["Label": "com.mimonitor.toolbox", "ProgramArguments": [path ?? executable.path, "--minimized"], "RunAtLoad": true, "ProcessType": "Interactive"]
        plist.merge(extras) { _, new in new }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
    private func temporary(_ test: (LegacyLoginItemFiles, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-login-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/LaunchAgents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try test(LegacyLoginItemFiles(home: root, executable: executable, bundleID: "com.mimonitor.toolbox", legacyStatus: { _ in .enabled }), root)
    }
    func testOwnershipRejectsMovedAppForeignIdentityExtraTriggersAndCorruption() throws {
        XCTAssertTrue(LegacyLoginItemFiles.owns(try data(), executable: executable, bundleID: "com.mimonitor.toolbox"))
        for bytes in [try data(path: "/Old/Toolbox.app/Contents/MacOS/MimonitorToolbox"), try data(extras: ["KeepAlive": true]), Data("bad".utf8)] {
            XCTAssertFalse(LegacyLoginItemFiles.owns(bytes, executable: executable, bundleID: "com.mimonitor.toolbox"))
        }
        XCTAssertFalse(LegacyLoginItemFiles.owns(try data(), executable: executable, bundleID: "foreign.app"))
    }
    func testBackupRetireRestorePreservesExactBytesAndDoesNotNeedLaunchctl() throws {
        try temporary { files, root in
            let bytes = try data(); try bytes.write(to: files.url)
            let record = try XCTUnwrap(files.read())
            try files.backup(record); try files.retire(record)
            XCTAssertNil(try files.read())
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Application Support/MimonitorToolbox/LoginItemMigration").path))
            try files.restore(record); XCTAssertEqual(try Data(contentsOf: files.url), bytes)
        }
    }
    func testChangedFileCannotBeRetiredOrOverwrittenByRestore() throws {
        try temporary { files, _ in
            try data().write(to: files.url)
            let record = try XCTUnwrap(files.read()); try files.backup(record)
            let foreign = try data(extras: ["KeepAlive": true]); try foreign.write(to: files.url)
            XCTAssertThrowsError(try files.retire(record)); XCTAssertThrowsError(try files.restore(record))
            XCTAssertEqual(try Data(contentsOf: files.url), foreign)
        }
    }
    func testSymlinkIsPreservedAndNeverTreatedAsOwned() throws {
        try temporary { files, root in
            let target = root.appendingPathComponent("foreign.plist"); let bytes = try data()
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(at: files.url, withDestinationURL: target)
            let record = try XCTUnwrap(files.read()); XCTAssertEqual(record.status, .unrecognized)
            XCTAssertThrowsError(try files.backup(record)); XCTAssertEqual(try Data(contentsOf: target), bytes)
        }
    }
}

@MainActor final class LoginItemCoordinatorTests: XCTestCase {
    func testMockReadbackMatchesToggleAndDoesNotUseADBOrLiveServices() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.setAutostart(true)
        await state.waitForPendingWork()
        XCTAssertTrue(state.settings.autostartEnabled); XCTAssertFalse(state.settings.loginItemBusy)
        state.setAutostart(false); await state.waitForPendingWork()
        XCTAssertFalse(state.settings.autostartEnabled)
        XCTAssertEqual(runtime.effects.filter { $0 == "login.write" }.count, 2)
        XCTAssertTrue(runtime.display.recordedCommands.isEmpty)
    }
    func testSwitchingADBTargetsDoesNotCancelLoginChange() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.setAutostart(true); state.adb.beginSession(ip: "192.0.2.2")
        await state.waitForPendingWork()
        XCTAssertTrue(state.settings.autostartEnabled)
    }
    func testStoppingDropsQueuedLoginMutationAndReleasesBusyFlag() async {
        let runtime = PreviewRuntime(), state = runtime.makeState()
        state.systemQueue.suspend(); state.setAutostart(true); state.stop(); state.systemQueue.resume()
        let done = expectation(description: "system queue drained")
        state.systemQueue.async { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(state.settings.loginItemBusy)
        XCTAssertFalse(runtime.effects.contains("login.write"))
    }
}
