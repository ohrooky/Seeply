import AppKit
import Combine
import UniformTypeIdentifiers

/// Providers stay on MainActor. Only immutable URL values cross from their
/// completion queues back into UI state; no Task captures a provider array.
@MainActor
final class FileDropLoader: ObservableObject {
    private var batchID: UUID?
    private var remaining = 0
    private var results: [URL?] = []
    private var progress: [Progress] = []
    private var completion: (([URL]) -> Void)?

    @discardableResult
    func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) -> Bool {
        cancel()
        let providers = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                && $0.canLoadObject(ofClass: NSURL.self)
        }
        guard !providers.isEmpty else { return false }
        let id = UUID()
        batchID = id
        remaining = providers.count
        results = Array(repeating: nil, count: providers.count)
        self.completion = completion
        for (index, provider) in providers.enumerated() {
            let request = provider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
                let candidate = object as? URL
                let url = candidate.flatMap { $0.isFileURL ? $0 : nil }
                Task { @MainActor [weak self] in
                    self?.receive(url, at: index, batchID: id)
                }
            }
            progress.append(request)
        }
        return true
    }

    func cancel() {
        batchID = nil
        for request in progress { request.cancel() }
        progress.removeAll()
        results.removeAll()
        remaining = 0
        completion = nil
    }

    private func receive(_ url: URL?, at index: Int, batchID id: UUID) {
        guard batchID == id else { return }
        results[index] = url
        remaining -= 1
        guard remaining == 0 else { return }
        let urls = results.compactMap { $0 }
        let completion = self.completion
        batchID = nil
        self.completion = nil
        progress.removeAll()
        results.removeAll()
        completion?(urls)
    }
}
