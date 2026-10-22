import Foundation
import Combine

/// Ties the durable application queue to the on-demand, supervised ACE engine.
/// An inactive, Cineo-owned server is reclaimed after 10 minutes; externally
/// launched servers are never stopped or adopted by this coordinator.
@MainActor
final class CineoMusicRuntimeCoordinator {
    private let queue: CineoMusicJobQueue
    private let backend: CineoACEBackendController
    private var subscriptions = Set<AnyCancellable>()
    private var idleTask: Task<Void, Never>?
    private let idleSeconds: Int64 = 600

    init(queue: CineoMusicJobQueue, backend: CineoACEBackendController) {
        self.queue = queue
        self.backend = backend
        queue.configureEngine { [weak backend] in
            guard let backend else { throw CancellationError() }
            try await backend.ensureReady()
        }
        Publishers.CombineLatest(queue.$jobs, backend.$phase)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            }
            .store(in: &subscriptions)
    }

    private func reconcile() {
        idleTask?.cancel()
        idleTask = nil
        guard !queue.hasWork, backend.isManaged, backend.isReady else { return }
        let timeout = idleSeconds
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, !self.queue.hasWork,
                  self.backend.isManaged, self.backend.isReady else { return }
            self.backend.stop()
        }
    }
}
