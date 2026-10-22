import Foundation

/// A result with one producer. Submission is synchronous (preserves FIFO ordering), awaiting never
/// blocks a Swift cooperative thread, and task cancellation reaches queued/running work alike.
package struct BlockingJob<Value: Sendable>: Sendable {
    package let cancellation: CommandCancellation
    private let results: AsyncStream<Result<Value, Error>>
    fileprivate init(cancellation: CommandCancellation, results: AsyncStream<Result<Value, Error>>) {
        self.cancellation = cancellation; self.results = results
    }
    package func value() async throws -> Value {
        try await withTaskCancellationHandler {
            for await result in results { try Task.checkCancellation(); return try result.get() }
            throw CancellationError()
        } onCancel: { cancellation.cancel() }
    }
}

package struct BlockingExecutor: Sendable {
    private let queue: DispatchQueue
    package init(queue: DispatchQueue) { self.queue = queue }
    package func submit<Value: Sendable>(cancellation: CommandCancellation = CommandCancellation(),
                                         _ work: @escaping @Sendable () throws -> Value) -> BlockingJob<Value> {
        let (stream, continuation) = AsyncStream<Result<Value, Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        queue.async {
            defer { continuation.finish() }
            guard !cancellation.isCancelled else { continuation.yield(.failure(CancellationError())); return }
            do {
                let value = try work()
                if cancellation.isCancelled { continuation.yield(.failure(CancellationError())) }
                else { continuation.yield(.success(value)) }
            } catch { continuation.yield(.failure(error)) }
        }
        return BlockingJob(cancellation: cancellation, results: stream)
    }
}

/// Event entry points need root tasks; their owner cancels and releases all of them on shutdown.
/// Completions and handle bookkeeping are isolated to MainActor. No detached Tasks or lost errors.
@MainActor package final class OwnedWorkSet {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    package init() {}
    package var count: Int { tasks.count }
    package func observe<Value>(_ job: BlockingJob<Value>,
                                completion: @escaping @MainActor (Result<Value, Error>) -> Void = { _ in }) {
        let id = UUID()
        tasks[id] = Task { [weak self] in
            let result: Result<Value, Error>
            do { result = .success(try await job.value()) }
            catch { result = .failure(error) }
            self?.tasks.removeValue(forKey: id)
            guard !Task.isCancelled else { return }
            completion(result)
        }
    }
    package func waitForAll() async {
        while !tasks.isEmpty {
            let batch = Array(tasks.values)
            for task in batch { await task.value }
        }
    }
    package func cancelAll() {
        tasks.values.forEach { $0.cancel() }; tasks.removeAll()
    }
    deinit { tasks.values.forEach { $0.cancel() } }
}
