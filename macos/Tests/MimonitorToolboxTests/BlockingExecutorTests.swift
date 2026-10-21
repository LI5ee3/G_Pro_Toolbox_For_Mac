import XCTest
import Foundation
import Synchronization
import ToolboxConcurrency

final class BlockingExecutorTests: XCTestCase {
    func testFIFOTransactionsCannotInterleaveAcrossAwaitingTasks() async throws {
        let executor = BlockingExecutor(queue: DispatchQueue(label: "test.serial"))
        let order = Mutex<[Int]>([])
        let first = executor.submit {
            order.withLock { $0.append(1) }
            Thread.sleep(forTimeInterval: 0.02)
            order.withLock { $0.append(2) }
            return 10
        }
        let second = executor.submit { order.withLock { $0.append(3) }; return 20 }
        async let a = first.value()
        async let b = second.value()
        let values = try await (a, b)
        XCTAssertEqual(values.0, 10); XCTAssertEqual(values.1, 20)
        XCTAssertEqual(order.withLock { $0 }, [1, 2, 3])
    }
    func testCancellingAwaiterStopsRunningBlockingOperation() async {
        let executor = BlockingExecutor(queue: DispatchQueue(label: "test.cancel"))
        let token = CommandCancellation()
        let began = expectation(description: "blocking operation began")
        let ended = expectation(description: "blocking operation cooperatively ended")
        let job = executor.submit(cancellation: token) {
            began.fulfill()
            defer { ended.fulfill() }
            return token.sleep(for: 10)
        }
        let task = Task { try await job.value() }
        await fulfillment(of: [began], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("cancellation lost") } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [ended], timeout: 1)
        XCTAssertTrue(token.isCancelled)
    }
    func testCancelledQueuedWorkDoesNotRunAndSiblingStillRuns() async throws {
        let queue = DispatchQueue(label: "test.queued")
        queue.suspend()
        let executor = BlockingExecutor(queue: queue), token = CommandCancellation()
        let bad = executor.submit(cancellation: token) { XCTFail("cancelled queued work ran"); return 0 }
        let good = executor.submit { 42 }
        token.cancel(); queue.resume()
        do { _ = try await bad.value(); XCTFail("queued cancellation lost") } catch { XCTAssertTrue(error is CancellationError) }
        let result = try await good.value(); XCTAssertEqual(result, 42)
    }
    func testChildCancellationDoesNotCancelParentOrSibling() {
        let parent = CommandCancellation(), child: CommandCancellation
        child = CommandCancellation(parent: parent)
        let sibling = CommandCancellation(parent: parent)
        child.cancel(); XCTAssertTrue(child.isCancelled)
        XCTAssertFalse(parent.isCancelled); XCTAssertFalse(sibling.isCancelled)
        parent.cancel(); XCTAssertTrue(sibling.isCancelled)
    }
    func testThrowingWorkDeliversItsErrorInsteadOfHanging() async {
        enum TestError: Error { case expected }
        let executor = BlockingExecutor(queue: DispatchQueue(label: "test.error"))
        let job: BlockingJob<Int> = executor.submit { throw TestError.expected }
        do { _ = try await job.value(); XCTFail("error lost") } catch { XCTAssertTrue(error is TestError) }
    }
    @MainActor func testWorkOwnerReleasesCompletedAndCancelledHandles() async throws {
        let owner = OwnedWorkSet(), queue = DispatchQueue(label: "test.owner")
        let finished = expectation(description: "typed completion")
        owner.observe(BlockingExecutor(queue: queue).submit { 42 }) { result in
            XCTAssertEqual(try? result.get(), 42); finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(owner.count, 0)
        queue.suspend()
        let token = CommandCancellation()
        owner.observe(BlockingExecutor(queue: queue).submit(cancellation: token) { XCTFail("shutdown work ran"); return 0 })
        owner.cancelAll()
        await Task.yield()
        queue.resume()
        let barrier = BlockingExecutor(queue: queue).submit { true }
        _ = try await barrier.value()
        XCTAssertEqual(owner.count, 0); XCTAssertTrue(token.isCancelled)
    }
}
