import XCTest
#if canImport(SeeplyCore)
@testable import SeeplyCore
#else
@testable import Seeply
#endif

private enum PoolTestError: Error { case expectedFailure, timeout }

/// Deliberately ignores cancellation, like an ImageIO decode already running.
private actor DecodeGate {
    private(set) var starts = 0
    private(set) var returned = 0
    private var continuations: [Int: CheckedContinuation<Int, Error>] = [:]

    func run() async throws -> Int {
        starts += 1
        let id = starts
        do {
            let value: Int = try await withCheckedThrowingContinuation { continuations[id] = $0 }
            returned += 1
            return value
        } catch {
            returned += 1
            throw error
        }
    }

    func resolve(_ id: Int, _ result: Result<Int, Error>) {
        continuations.removeValue(forKey: id)?.resume(with: result)
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
    }
}

private actor CompletionRecorder {
    private(set) var result: Int?
    func store(_ value: Int) { result = value }
}

@MainActor
final class SharedRequestPoolTests: XCTestCase {
    private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard clock.now < deadline else { throw PoolTestError.timeout }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    func testConcurrentEqualKeysRunOnlyOneOperation() async throws {
        let pool = SharedRequestPool<String, Int>()
        let gate = DecodeGate()
        defer { Task { await gate.releaseAll() } }
        let first = Task { try await pool.value(for: "same") { try await gate.run() } }
        let second = Task { try await pool.value(for: "same") { try await gate.run() } }
        let third = Task { try await pool.value(for: "same") { try await gate.run() } }
        try await eventually { await pool.waiterCount(for: "same") == 3 }
        try await eventually { await gate.starts == 1 }
        let starts = await gate.starts
        XCTAssertEqual(starts, 1)
        await gate.resolve(1, .success(42))
        let values = try await [first.value, second.value, third.value]
        XCTAssertEqual(values, [42, 42, 42])
        let remaining = await pool.waiterCount(for: "same")
        XCTAssertEqual(remaining, 0)
    }

    func testCancellingOneWaiterLeavesTheOtherWaiting() async throws {
        let pool = SharedRequestPool<String, Int>()
        let gate = DecodeGate()
        defer { Task { await gate.releaseAll() } }
        let first = Task { try await pool.value(for: "same") { try await gate.run() } }
        let second = Task { try await pool.value(for: "same") { try await gate.run() } }
        try await eventually { await pool.waiterCount(for: "same") == 2 }
        try await eventually { await gate.starts == 1 }
        first.cancel()
        do { _ = try await first.value; XCTFail("A cancelled waiter must finish immediately") }
        catch { XCTAssertTrue(error is CancellationError) }
        let remaining = await pool.waiterCount(for: "same")
        XCTAssertEqual(remaining, 1)
        await gate.resolve(1, .success(7))
        let value = try await second.value
        let starts = await gate.starts
        XCTAssertEqual(value, 7)
        XCTAssertEqual(starts, 1)
    }

    func testLateCancelledOperationCannotRetireAReplacementWithTheSameKey() async throws {
        let pool = SharedRequestPool<String, Int>()
        let gate = DecodeGate()
        let recorder = CompletionRecorder()
        defer { Task { await gate.releaseAll() } }
        let old = Task { try await pool.value(for: "same") { try await gate.run() } }
        try await eventually { await gate.starts == 1 }
        old.cancel()
        do { _ = try await old.value; XCTFail("The last waiter must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        let replacement = Task {
            let value = try await pool.value(for: "same") { try await gate.run() }
            await recorder.store(value)
            return value
        }
        try await eventually { await gate.starts == 2 }
        await gate.resolve(1, .success(100))
        try await eventually { await gate.returned == 1 }
        await gate.resolve(2, .success(200))
        // A lost replacement continuation fails with a deadline, rather than hanging the suite.
        try await eventually { await recorder.result != nil }
        let value = try await replacement.value
        XCTAssertEqual(value, 200)
    }

    func testFailureReachesAllWaitersAndTheKeyCanBeRetried() async throws {
        let pool = SharedRequestPool<String, Int>()
        let gate = DecodeGate()
        defer { Task { await gate.releaseAll() } }
        let first = Task { try await pool.value(for: "same") { try await gate.run() } }
        let second = Task { try await pool.value(for: "same") { try await gate.run() } }
        try await eventually { await pool.waiterCount(for: "same") == 2 }
        try await eventually { await gate.starts == 1 }
        await gate.resolve(1, .failure(PoolTestError.expectedFailure))
        for task in [first, second] {
            do { _ = try await task.value; XCTFail("Decode failure must reach every waiter") }
            catch { XCTAssertTrue(error is PoolTestError) }
        }
        let retry = try await pool.value(for: "same") { 99 }
        XCTAssertEqual(retry, 99)
    }

    func testDifferentKeysDoNotShareAnOperation() async throws {
        let pool = SharedRequestPool<String, Int>()
        let gate = DecodeGate()
        defer { Task { await gate.releaseAll() } }
        let first = Task { try await pool.value(for: "a") { try await gate.run() } }
        let second = Task { try await pool.value(for: "b") { try await gate.run() } }
        try await eventually { await gate.starts == 2 }
        await gate.resolve(1, .success(1))
        await gate.resolve(2, .success(2))
        let values = try await [first.value, second.value]
        XCTAssertEqual(Set(values), Set([1, 2]))
    }
}
