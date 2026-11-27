import Foundation

/// A cancellation-aware bridge for blocking ImageIO / FileManager work.
/// Cancellation resumes the waiter immediately, while the retained input lease
/// remains alive until an already-running decoder really returns.
final class WorkQueue: @unchecked Sendable {
    private let queue: OperationQueue

    init(name: String, concurrency: Int, qos: QualityOfService) {
        queue = OperationQueue()
        queue.name = name
        queue.maxConcurrentOperationCount = concurrency
        queue.qualityOfService = qos
    }

    func run<T: Sendable>(priority: Operation.QueuePriority = .normal,
                          _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let ticket = WorkTicket<T>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                ticket.attach(continuation)
                let operation = BlockOperation {
                    guard !ticket.isFinished else { return }
                    let result = autoreleasepool { Result { try work() } }
                    ticket.finish(result)
                }
                operation.queuePriority = priority
                ticket.attach(operation)
                queue.addOperation(operation)
            }
        }, onCancel: { ticket.cancel() })
    }
}

private final class WorkTicket<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var operation: Operation?
    private var result: Result<T, Error>?

    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return result != nil
    }

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func attach(_ operation: Operation) {
        lock.lock()
        let finished = result != nil
        if !finished { self.operation = operation }
        lock.unlock()
        if finished { operation.cancel() }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        operation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        let operation = self.operation
        lock.unlock()
        operation?.cancel()
        finish(.failure(CancellationError()))
    }
}
