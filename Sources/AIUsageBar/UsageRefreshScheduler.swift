import Foundation

// MARK: - Snapshot reset dates

protocol UsageSnapshotResets: Sendable {
    var resetDates: [Date?] { get }
}

// MARK: - Shared refresh scheduling

@MainActor
enum UsageRefreshScheduler {
    /// Schedule a one-shot refresh at the soonest reset time among the given snapshot.
    /// Returns a cancellable task, or nil when no reset date is available.
    static func scheduleResetRefresh(
        from snapshot: (some UsageSnapshotResets)?,
        refresh: @escaping () async -> Void
    ) -> Task<Void, Never>? {
        let dates = snapshot?.resetDates ?? []
        let nextReset = dates.compactMap { $0 }.min()
        guard let nextReset else { return nil }

        return Task {
            let delaySeconds = max(0, nextReset.timeIntervalSinceNow) + 3
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Start the standard refresh loop: initial delay → refresh → periodic loop.
    static func startRefreshLoop(
        initialDelaySeconds: Double,
        refreshIntervalSeconds: @escaping () -> Double,
        refresh: @escaping () async -> Void
    ) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(initialDelaySeconds))
            guard !Task.isCancelled else { return }

            await refresh()

            while !Task.isCancelled {
                let interval = max(60.0, refreshIntervalSeconds())
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }
}

/// One cancellable request per provider. The generation prevents a result from an
/// old enablement or connection being published after the provider is enabled again.
@MainActor
final class ProviderRefreshWork {
    private var active: Task<Void, Never>?
    private(set) var generation = 0

    deinit { self.active?.cancel() }

    @discardableResult
    func start(_ run: @escaping @MainActor (Int) async -> Void) -> Task<Void, Never>? {
        guard !Task.isCancelled else { return nil }
        if let active = self.active { return active }
        let generation = self.generation
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await run(generation)
            if self?.generation == generation { self?.active = nil }
        }
        self.active = task
        return task
    }

    func cancel() {
        self.generation += 1
        self.active?.cancel()
        self.active = nil
    }
}
