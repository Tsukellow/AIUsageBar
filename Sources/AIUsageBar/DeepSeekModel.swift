import Foundation
import SwiftUI

@MainActor
final class DeepSeekModel: ObservableObject {
    @Published private(set) var snapshot: DeepSeekUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    @Published var isEnabled: Bool {
        didSet {
            guard self.isEnabled != oldValue else { return }
            AppSettings.deepSeekEnabled = self.isEnabled
            if self.isEnabled {
                self.startLoop()
                self.refreshNow()
            } else {
                self.stopLoop()
            }
        }
    }

    private let service = DeepSeekUsageService()
    private let initialRefreshDelaySeconds: Double
    private let initialRefreshDueAt: Date
    private var refreshTask: Task<Void, Never>?
    private let refreshWork = ProviderRefreshWork()
    private var scheduledResetRefreshTask: Task<Void, Never>?

    init() {
        self.initialRefreshDelaySeconds = AppSettings.initialRefreshDelaySeconds
        self.initialRefreshDueAt = Date().addingTimeInterval(self.initialRefreshDelaySeconds)
        self.isEnabled = AppSettings.deepSeekEnabled
        if self.isEnabled {
            self.startLoop()
        }
    }

    deinit {
        self.refreshTask?.cancel()
        self.scheduledResetRefreshTask?.cancel()
    }

    // MARK: - Loop control

    private func startLoop() {
        self.stopLoop()
        self.refreshTask = UsageRefreshScheduler.startRefreshLoop(
            initialDelaySeconds: self.initialRefreshDelaySeconds,
            refreshIntervalSeconds: { AppSettings.refreshIntervalSeconds }
        ) { [weak self] in
            await self?.requestRefresh()?.value
        }
    }

    private func stopLoop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.scheduledResetRefreshTask?.cancel()
        self.scheduledResetRefreshTask = nil
        self.refreshWork.cancel()
        self.isRefreshing = false
        self.snapshot = nil
        self.errorMessage = nil
    }

    // MARK: - Menu bar properties

    var menuBarRingFraction: Double {
        guard let balance = self.snapshot?.balance else { return 0 }
        return AppSettings.deepSeekBalanceSettings().ringFraction(for: balance)
    }

    var menuBarTopText: String {
        guard let todayCost = self.snapshot?.todayCost else { return "--" }
        return String(format: "%.2f", todayCost)
    }

    var menuBarBottomText: String {
        guard let snapshot = self.snapshot else { return "--" }
        return String(format: "%.2f", snapshot.balance)
    }

    var menuBarCenterSymbol: CenterSymbol? {
        guard let snapshot = self.snapshot else { return nil }
        return AppSettings.deepSeekBalanceSettings().isLowBalance(snapshot.balance) ? .exclamation : .checkmark
    }

    var pendingInitialRefreshDueAt: Date? {
        guard self.snapshot == nil,
              !self.isRefreshing,
              self.errorMessage == nil,
              !AppSettings.deepSeekBearerToken.isEmpty,
              Date() < self.initialRefreshDueAt else {
            return nil
        }
        return self.initialRefreshDueAt
    }

    // MARK: - Actions

    func refreshNow() {
        _ = self.requestRefresh()
    }

    private func requestRefresh() -> Task<Void, Never>? {
        guard self.isEnabled else { return nil }
        return self.refreshWork.start { [weak self] generation in
            await self?.refresh(generation: generation)
        }
    }

    // MARK: - Refresh

    private func refresh(generation: Int) async {
        let token = AppSettings.deepSeekBearerToken
        guard !token.isEmpty else {
            self.scheduledResetRefreshTask?.cancel()
            self.errorMessage = "No DeepSeek token configured."
            return
        }

        guard !self.isRefreshing else { return }

        self.isRefreshing = true
        defer {
            if generation == self.refreshWork.generation { self.isRefreshing = false }
        }

        do {
            let snap = try await self.service.fetchSnapshot()
            guard !Task.isCancelled, generation == self.refreshWork.generation else { return }
            self.snapshot = snap
            self.errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == self.refreshWork.generation else { return }
            self.errorMessage = error.localizedDescription
        }
    }
}
