import ToolboxDomain
import ToolboxApplication
import ToolboxConcurrency
import Foundation
import ServiceManagement
import CryptoKit

/// SMAppService.mainApp is the only new registration path. No helper, daemon or privilege grant.
package final class LiveLoginItems {
    private let service: SMAppService
    private let legacy: LegacyLoginItemFiles
    private var workflow: LoginItemWorkflow {
        let service = service, legacy = legacy
        return LoginItemWorkflow(ports: LoginItemPorts(
            status: { Self.map(service.status) }, register: { try service.register() },
            unregister: { try service.unregister() }, legacy: { try legacy.read() },
            backup: { try legacy.backup($0) }, retire: { try legacy.retire($0) },
            restore: { try legacy.restore($0) }))
    }
    package init(bundle: Bundle = .main) {
        service = .mainApp
        legacy = LegacyLoginItemFiles(home: FileManager.default.homeDirectoryForCurrentUser,
            executable: bundle.executableURL, bundleID: bundle.bundleIdentifier)
    }
    package func read() -> LoginItemSnapshot { workflow.snapshot() }
    package func reconcile(_ token: CommandCancellation) -> LoginItemSnapshot { workflow.reconcile(token) }
    package func setEnabled(_ enabled: Bool, token: CommandCancellation) -> LoginItemSnapshot { workflow.setEnabled(enabled, cancellation: token) }
    package static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    private static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unavailable
        }
    }
}

/// Restrict retirement to the exact legacy shape and the running app's executable. Moving an app
/// leaves an unverified old path: preserve it for manual review instead of registering a duplicate.
package final class LegacyLoginItemFiles {
    private static let label = "com.mimonitor.toolbox"
    private let manager = FileManager.default
    private let home: URL
    private let executable: URL?
    private let bundleID: String?
    private let legacyStatus: (URL) -> SMAppService.Status
    package init(home: URL, executable: URL?, bundleID: String?,
                 legacyStatus: @escaping (URL) -> SMAppService.Status = SMAppService.statusForLegacyPlist(at:)) {
        self.home = home; self.executable = executable; self.bundleID = bundleID; self.legacyStatus = legacyStatus
    }
    package var url: URL { home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist") }
    private var backups: URL { home.appendingPathComponent("Library/Application Support/MimonitorToolbox/LoginItemMigration") }
    private func backupURL(_ record: LegacyLoginItemRecord) -> URL {
        let digest = SHA256.hash(data: record.bytes).map { String(format: "%02x", $0) }.joined()
        return backups.appendingPathComponent("\(digest).plist")
    }
    package static func owns(_ data: Data, executable: URL?, bundleID: String?) -> Bool {
        guard bundleID == label, let executable, executable.lastPathComponent == "MimonitorToolbox",
              executable.path.contains(".app/Contents/MacOS/"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              Set(plist.keys) == Set(["Label", "ProgramArguments", "RunAtLoad", "ProcessType"]),
              plist["Label"] as? String == label, plist["RunAtLoad"] as? Bool == true,
              plist["ProcessType"] as? String == "Interactive",
              let args = plist["ProgramArguments"] as? [String], args.count == 2, args[1] == "--minimized",
              URL(fileURLWithPath: args[0]).standardizedFileURL == executable.standardizedFileURL else { return false }
        return true
    }
    package func read() throws -> LegacyLoginItemRecord? {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try manager.attributesOfItem(atPath: url.path) }
        catch CocoaError.fileReadNoSuchFile { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            return LegacyLoginItemRecord(bytes: Data(), status: .unrecognized)
        }
        let bytes = try Data(contentsOf: url)
        guard Self.owns(bytes, executable: executable, bundleID: bundleID) else {
            return LegacyLoginItemRecord(bytes: bytes, status: .unrecognized)
        }
        let status = legacyStatus(url)
        return LegacyLoginItemRecord(bytes: bytes, status: status == .requiresApproval ? .disabled : .enabled)
    }
    package func backup(_ record: LegacyLoginItemRecord) throws {
        guard try read()?.bytes == record.bytes, record.status != .unrecognized else { throw CocoaError(.fileReadUnknown) }
        try manager.createDirectory(at: backups, withIntermediateDirectories: true)
        let target = backupURL(record)
        if manager.fileExists(atPath: target.path) {
            guard try Data(contentsOf: target) == record.bytes else { throw CocoaError(.fileWriteFileExists) }
        } else { try record.bytes.write(to: target, options: .atomic) }
    }
    package func retire(_ record: LegacyLoginItemRecord) throws {
        guard let current = try read(), current.status != .unrecognized, current.bytes == record.bytes,
              try Data(contentsOf: backupURL(record)) == record.bytes else { throw CocoaError(.fileReadUnknown) }
        // No bootout: that could kill this very process when it was launched by the old job.
        // Exact legacy shape excludes KeepAlive and all other triggers, so removing its plist
        // prevents the next GUI-domain login from loading it; the current job ends normally.
        try manager.moveItem(at: url, to: backups.appendingPathComponent("retired-\(UUID().uuidString).plist"))
    }
    package func restore(_ record: LegacyLoginItemRecord) throws {
        if let current = try read() {
            guard current.bytes == record.bytes else { throw CocoaError(.fileWriteFileExists) }
            return
        }
        guard try Data(contentsOf: backupURL(record)) == record.bytes else { throw CocoaError(.fileReadCorruptFile) }
        try record.bytes.write(to: url, options: .atomic)
    }
}
