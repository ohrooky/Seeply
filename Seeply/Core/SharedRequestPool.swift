import Foundation

/// Coalesces equal requests while keeping each caller's cancellation independent.
/// Only the final cancelled waiter cancels the shared operation. A job identity
/// prevents an old, non-cooperative operation from retiring a newer equal job.
actor SharedRequestPool<Key: Hashable & Sendable, Value: Sendable> {
    private struct Job {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value, Error>]
    }
    private var jobs: [Key: Job] = [:]

    func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let waiterID = UUID()
        let value: Value = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if var job = jobs[key] {
                    job.waiters[waiterID] = continuation
                    jobs[key] = job
                    return
                }
                let jobID = UUID()
                let task = Task { [weak self] in
                    let result: Result<Value, Error>
                    do { result = .success(try await operation()) }
                    catch { result = .failure(error) }
                    await self?.finish(key, jobID: jobID, result: result)
                }
                jobs[key] = Job(id: jobID, task: task, waiters: [waiterID: continuation])
            }
        }, onCancel: {
            Task { await self.cancel(waiterID, for: key) }
        })
        try Task.checkCancellation()
        return value
    }

    private func finish(_ key: Key, jobID: UUID, result: Result<Value, Error>) {
        guard let job = jobs[key], job.id == jobID else { return }
        jobs.removeValue(forKey: key)
        for waiter in job.waiters.values { waiter.resume(with: result) }
    }

    private func cancel(_ waiterID: UUID, for key: Key) {
        guard var job = jobs[key], let waiter = job.waiters.removeValue(forKey: waiterID) else { return }
        if job.waiters.isEmpty {
            jobs.removeValue(forKey: key)
            job.task.cancel()
        } else {
            jobs[key] = job
        }
        waiter.resume(throwing: CancellationError())
    }

    // Internal observability also lets the concurrency regression tests synchronize
    // on registrations, rather than assuming that a sleep implies a task has started.
    func waiterCount(for key: Key) -> Int { jobs[key]?.waiters.count ?? 0 }
}
