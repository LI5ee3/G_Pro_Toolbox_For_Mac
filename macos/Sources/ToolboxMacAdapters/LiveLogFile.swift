import Foundation
import AppKit
import Synchronization
import ToolboxDomain
import ToolboxApplication

/// File handles and filesystem operations belong to one serial writer. Metadata has a separate
/// short lock, so opening the log UI or observing an error never waits behind a filesystem write.
package final class LiveLogFile: Sendable {
    private final class Storage: Sendable {
        struct State { var url: URL?; var handle: FileHandle?; var reportedFailure = false }
        let state = Mutex(State())
    }
    private final class Metadata: Sendable {
        struct State {
            var url: URL?
            var observer: UUID?
            var handler: (@MainActor @Sendable (String) -> Void)?
        }
        let state = Mutex(State())
    }
    private let directory: URL
    private let queue = DispatchQueue(label: "com.mimonitor.toolbox.log-writer", qos: .utility)
    private let storage = Storage(), metadata = Metadata()
    package init(directory: URL) { self.directory = directory }
    @MainActor package func observeErrors(_ handler: @escaping @MainActor @Sendable (String) -> Void) -> RuntimeCancellation {
        let id = UUID()
        metadata.state.withLock { $0.observer = id; $0.handler = handler }
        return RuntimeCancellation { [self] in
            metadata.state.withLock { if $0.observer == id { $0.observer = nil; $0.handler = nil } }
        }
    }
    package func start(_ stamp: String) {
        let observer = metadata.state.withLock { $0.observer }
        queue.async { [self] in
            let issue = storage.state.withLock { state -> String? in
                try? state.handle?.close(); state.handle = nil; state.reportedFailure = false
                do {
                    guard !stamp.contains("/"), !stamp.utf8.contains(0) else { throw CocoaError(.fileWriteInvalidFileName) }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent("log_\(stamp).txt")
                    if !FileManager.default.fileExists(atPath: url.path) {
                        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                    }
                    let handle = try FileHandle(forWritingTo: url)
                    do { _ = try handle.seekToEnd() } catch { try? handle.close(); throw error }
                    state.handle = handle; state.url = url
                    metadata.state.withLock { $0.url = url }
                    return nil
                } catch { return Self.fail(error, state: &state) }
            }
            if let issue { notify(issue, observer: observer) }
        }
    }
    package func append(_ line: String) {
        let observer = metadata.state.withLock { $0.observer }
        let bytes = Data(line.utf8)
        queue.async { [self] in
            let issue = storage.state.withLock { state -> String? in
                guard let handle = state.handle else { return nil }
                do { try handle.write(contentsOf: bytes); return nil }
                catch { return Self.fail(error, state: &state) }
            }
            if let issue { notify(issue, observer: observer) }
        }
    }
    package func stop() {
        let observer = metadata.state.withLock { $0.observer }
        queue.async { [self] in
            let issue = storage.state.withLock { state -> String? in
                do { try state.handle?.close(); state.handle = nil; return nil }
                catch { return Self.fail(error, state: &state) }
            }
            if let issue { notify(issue, observer: observer) }
        }
    }
    package func export(_ target: URL, text: String, completion: @escaping @MainActor @Sendable (FileActionResult) -> Void) {
        queue.async { [self] in
            let result: FileActionResult = storage.state.withLock { state in
                do {
                    if let handle = state.handle, let source = state.url {
                        try handle.synchronize()
                        if source.resolvingSymlinksInPath() == target.resolvingSymlinksInPath() { return .success }
                        let temporary = target.deletingLastPathComponent().appendingPathComponent(".ToolboxExport-\(UUID().uuidString)")
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        try FileManager.default.copyItem(at: source, to: temporary)
                        if FileManager.default.fileExists(atPath: target.path) {
                            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
                        } else { try FileManager.default.moveItem(at: temporary, to: target) }
                    } else { try text.write(to: target, atomically: true, encoding: .utf8) }
                    return .success
                } catch { return .failure(error.localizedDescription) }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
    @MainActor package func open() {
        let observer = metadata.state.withLock { $0.observer }
        queue.async { [self] in
            let url = metadata.state.withLock { $0.url }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let existing = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                DispatchQueue.main.async {
                    if let existing { NSWorkspace.shared.activateFileViewerSelecting([existing]) }
                    else { NSWorkspace.shared.open(self.directory) }
                }
            } catch { notify(error.localizedDescription, observer: observer) }
        }
    }
    package func finish(_ completion: @escaping @MainActor @Sendable () -> Void) {
        queue.async { DispatchQueue.main.async { completion() } }
    }
    package func drain() async {
        await withCheckedContinuation { continuation in finish { continuation.resume() } }
    }
    private static func fail(_ error: Error, state: inout Storage.State) -> String? {
        try? state.handle?.close(); state.handle = nil
        guard !state.reportedFailure else { return nil }
        state.reportedFailure = true; return error.localizedDescription
    }
    private func notify(_ issue: String, observer id: UUID?) {
        guard id != nil else { return }
        DispatchQueue.main.async { [self] in
            let handler = metadata.state.withLock { state in state.observer == id ? state.handler : nil }
            handler?(issue)
        }
    }
    deinit {
        let storage = storage
        queue.async { storage.state.withLock { try? $0.handle?.close(); $0.handle = nil } }
    }
}
