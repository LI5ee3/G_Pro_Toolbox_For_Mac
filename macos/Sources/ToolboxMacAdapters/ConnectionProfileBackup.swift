import CryptoKit
import Darwin
import Foundation

/// Opaque, content-addressed local backups. Publication is atomic and never replaces a file.
/// Readback confirms the current filesystem view; this does not promise power-loss durability.
package enum ConnectionProfileBackup {
    package enum Failure: Error, LocalizedError {
        case invalidIdentifier, unavailableDirectory, unsafeDirectory, unsafeFile, contentMismatch
        package var errorDescription: String? {
            switch self {
            case .invalidIdentifier: return "连接备份标识无效或与内容摘要不一致"
            case .unavailableDirectory: return "无法确定连接备份目录"
            case .unsafeDirectory: return "连接备份目录类型、所有者或权限不安全"
            case .unsafeFile: return "连接备份文件类型、所有者或权限不安全"
            case .contentMismatch: return "连接备份回读与原内容不一致，未覆盖已有文件"
            }
        }
    }

    package static func write(_ data: Data, identifier: String, root: URL? = nil) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let isDigest = identifier.utf8.count == 64 && identifier.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
        let isUUID = UUID(uuidString: identifier)?.uuidString.lowercased() == identifier.lowercased()
        guard (isDigest && identifier.lowercased() == digest) || isUUID else { throw Failure.invalidIdentifier }
        let directoryURL: URL
        if let root { directoryURL = root }
        else {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw Failure.unavailableDirectory
            }
            directoryURL = support.appendingPathComponent("MimonitorToolbox/ConnectionBackups", isDirectory: true)
        }
        guard directoryURL.isFileURL else { throw Failure.unavailableDirectory }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directory = Darwin.open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw systemError() }
        defer { Darwin.close(directory) }
        var attributes = stat()
        guard fstat(directory, &attributes) == 0 else { throw systemError() }
        guard attributes.st_mode & S_IFMT == S_IFDIR, attributes.st_uid == geteuid() else {
            throw Failure.unsafeDirectory
        }
        guard fchmod(directory, 0o700) == 0, fstat(directory, &attributes) == 0 else { throw systemError() }
        guard attributes.st_mode & 0o7777 == 0o700 else { throw Failure.unsafeDirectory }

        // The identifier never becomes a path component; content hashing also protects UUID reuse.
        let name = digest + ".plist"
        if try verifyExisting(name, directory: directory, expected: data) { return }
        let temporary = ".pending-\(UUID().uuidString)"
        let file = openat(directory, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw systemError() }
        defer { Darwin.close(file); unlinkat(directory, temporary, 0) }
        guard fchmod(file, 0o600) == 0 else { throw systemError() }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw systemError(count == 0 ? EIO : errno) }
                offset += count
            }
        }
        try verify(file, expected: data)
        // Unlike rename/atomic replacement, linkat fails if any destination already exists.
        if linkat(directory, temporary, directory, name, 0) != 0 && errno != EEXIST { throw systemError() }
        guard try verifyExisting(name, directory: directory, expected: data) else { throw Failure.contentMismatch }
    }

    private static func verifyExisting(_ name: String, directory: Int32, expected: Data) throws -> Bool {
        // O_NONBLOCK prevents a pre-existing FIFO from blocking before its type is checked.
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if file < 0 {
            if errno == ENOENT { return false }
            throw systemError()
        }
        defer { Darwin.close(file) }
        try verify(file, expected: expected)
        return true
    }

    private static func verify(_ file: Int32, expected: Data) throws {
        var attributes = stat()
        guard fstat(file, &attributes) == 0 else { throw systemError() }
        guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == geteuid(),
              attributes.st_mode & 0o7777 == 0o600 else { throw Failure.unsafeFile }
        guard attributes.st_size == expected.count else { throw Failure.contentMismatch }
        guard lseek(file, 0, SEEK_SET) == 0 else { throw systemError() }
        var actual = Data(count: expected.count)
        try actual.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.read(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    if count == 0 { throw Failure.contentMismatch }
                    throw systemError()
                }
                offset += count
            }
        }
        guard actual == expected, SHA256.hash(data: actual) == SHA256.hash(data: expected) else {
            throw Failure.contentMismatch
        }
    }

    private static func systemError(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}
