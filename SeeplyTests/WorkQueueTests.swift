import XCTest
@testable import Seeply

final class WorkQueueTests: XCTestCase {
    func testCancellationResumesCallerEvenWhenWorkHasAlreadyStarted() async throws {
        let queue = WorkQueue(name: "test.cancellation", concurrency: 1, qos: .utility)
        let started = expectation(description: "work started")
        let release = DispatchSemaphore(value: 0)
        let completed = expectation(description: "worker eventually released")
        let task = Task {
            try await queue.run { () -> Int in
                started.fulfill()
                _ = release.wait(timeout: .now() + 5)
                completed.fulfill()
                return 42
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled waiter should not receive a decoded result")
        } catch { XCTAssertTrue(error is CancellationError) }
        release.signal()
        await fulfillment(of: [completed], timeout: 2)
    }
}
