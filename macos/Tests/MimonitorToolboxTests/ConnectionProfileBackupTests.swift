import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import ToolboxMacAdapters

final class ConnectionProfileBackupTests: XCTestCase {
    private func temporary(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-profile-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    func testBinaryPayloadRoundTripsExactlyWithPrivateDirectoryAndFile() throws {
        try temporary { parent in
            let root = parent.appendingPathComponent("new/backups"), data = Data([0, 255, 128, 65, 0, 10])
            try ConnectionProfileBackup.write(data, identifier: digest(data), root: root)
            let file = root.appendingPathComponent(digest(data) + ".plist")
            XCTAssertEqual(try Data(contentsOf: file), data)
            XCTAssertEqual(try permissions(root), 0o700)
            XCTAssertEqual(try permissions(file), 0o600)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.ownerAccountID] as? NSNumber)?.uint32Value, geteuid())
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
        }
    }

    func testRepeatedContentIsANoOpWithoutReplacingTheExistingFile() throws {
        try temporary { root in
            let data = Data("same protected bytes".utf8), identifier = digest(data)
            try ConnectionProfileBackup.write(data, identifier: identifier, root: root)
            let file = root.appendingPathComponent(identifier + ".plist")
            let before = try FileManager.default.attributesOfItem(atPath: file.path)
            try ConnectionProfileBackup.write(data, identifier: identifier.uppercased(), root: root)
            let after = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
            XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
        }
    }

    func testReusedUUIDPreservesBothDifferentContents() throws {
        try temporary { root in
            let identifier = UUID().uuidString
            let first = Data("first revision".utf8), second = Data("second revision".utf8)
            try ConnectionProfileBackup.write(first, identifier: identifier, root: root)
            try ConnectionProfileBackup.write(second, identifier: identifier.lowercased(), root: root)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(digest(first) + ".plist")), first)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(digest(second) + ".plist")), second)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        }
    }

    func testUnsafeOrMismatchedIdentifierDoesNotEvenCreateTheBackupDirectory() throws {
        try temporary { parent in
            let root = parent.appendingPathComponent("must-not-exist"), data = Data("original".utf8)
            for identifier in ["", "..", "../backup", "/absolute", "x/y", "x\\y", "bad\nname",
                               "not-a-uuid", String(repeating: "g", count: 64), String(repeating: "a", count: 64),
                               " \(UUID().uuidString)", "{\(UUID().uuidString)}"] {
                XCTAssertThrowsError(try ConnectionProfileBackup.write(data, identifier: identifier, root: root), identifier)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            }
        }
    }

    func testExistingDifferentBytesAreNeverOverwritten() throws {
        try temporary { root in
            let data = Data("expected".utf8), original = Data("conflict".utf8)
            let file = root.appendingPathComponent(digest(data) + ".plist")
            try original.write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let before = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertThrowsError(try ConnectionProfileBackup.write(data, identifier: digest(data), root: root))
            XCTAssertEqual(try Data(contentsOf: file), original)
            let after = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual(before[.systemFileNumber] as? NSNumber, after[.systemFileNumber] as? NSNumber)
            XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
        }
    }

    func testExistingTargetSymlinkIsRejectedWithoutChangingItsDestination() throws {
        try temporary { parent in
            let root = parent.appendingPathComponent("backups"), outside = parent.appendingPathComponent("outside")
            let data = Data("do not follow this path".utf8)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try data.write(to: outside)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outside.path)
            let file = root.appendingPathComponent(digest(data) + ".plist")
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
            XCTAssertThrowsError(try ConnectionProfileBackup.write(data, identifier: digest(data), root: root))
            XCTAssertEqual(try Data(contentsOf: outside), data)
            XCTAssertEqual(try permissions(outside), 0o600)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), outside.path)
        }
    }

    func testRootSymlinkIsRejectedWithoutWritingIntoItsDestination() throws {
        try temporary { parent in
            let actual = parent.appendingPathComponent("actual"), root = parent.appendingPathComponent("link")
            try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o755])
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: actual)
            let data = Data("private backup".utf8)
            XCTAssertThrowsError(try ConnectionProfileBackup.write(data, identifier: digest(data), root: root))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: actual.path).isEmpty)
            XCTAssertEqual(try permissions(actual), 0o755)
        }
    }

    func testExistingNonRegularTargetsAndPublicFilesAreRejected() throws {
        try temporary { parent in
            let data = Data("expected".utf8)
            for kind in ["directory", "fifo", "public-file"] {
                let root = parent.appendingPathComponent(kind)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                let file = root.appendingPathComponent(digest(data) + ".plist")
                switch kind {
                case "directory": try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                case "fifo": XCTAssertEqual(mkfifo(file.path, 0o600), 0)
                default:
                    try data.write(to: file)
                    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
                }
                XCTAssertThrowsError(try ConnectionProfileBackup.write(data, identifier: digest(data), root: root), kind)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
                if kind == "public-file" {
                    XCTAssertEqual(try Data(contentsOf: file), data)
                    XCTAssertEqual(try permissions(file), 0o644)
                }
            }
        }
    }

    func testExistingDirectoryIsTightenedBeforePublishingPrivateFile() throws {
        try temporary { root in
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            let data = Data()
            try ConnectionProfileBackup.write(data, identifier: digest(data), root: root)
            XCTAssertEqual(try permissions(root), 0o700)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(digest(data) + ".plist")), data)
            XCTAssertEqual(try permissions(root.appendingPathComponent(digest(data) + ".plist")), 0o600)
        }
    }

    func testConcurrentIdenticalBackupsPublishOneCompleteFileWithoutTemporaryResidue() throws {
        try temporary { root in
            let data = Data(repeating: 0xa5, count: 128 * 1024), identifier = digest(data)
            let lock = NSLock()
            var errors: [String] = []
            DispatchQueue.concurrentPerform(iterations: 12) { _ in
                do { try ConnectionProfileBackup.write(data, identifier: identifier, root: root) }
                catch { lock.lock(); errors.append(String(describing: error)); lock.unlock() }
            }
            XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
            let file = root.appendingPathComponent(identifier + ".plist")
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [file.lastPathComponent])
            XCTAssertEqual(try Data(contentsOf: file), data)
            XCTAssertEqual(try permissions(file), 0o600)
        }
    }
}
