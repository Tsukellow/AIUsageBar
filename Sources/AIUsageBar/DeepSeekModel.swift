import Foundation
import SwiftUI

@MainActor
final class DeepSeekModel: ObservableObject {
    @Published private(set) var snapshot: DeepSeekUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    @Published var isEnabled: Bool {
        didSet {
            AppSettings.deepSeekEnabled = self.isEnabled
            if !self.isEnabled && !AppSettings.claudeEnabled && !AppSettings.codexEnabled {
                self.isEnabled = true
                return
            }
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
            await self?.refresh()
        }
    }

    private func stopLoop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.scheduledResetRefreshTask?.cancel()
        self.scheduledResetRefreshTask = nil
        self.snapshot = nil
        self.errorMessage = nil
    }

    // MARK: - Menu bar properties

    var menuBarRingFraction: Double {
        guard let balance = self.snapshot?.balance, balance > 0 else { return 0 }
        let threshold = AppSettings.deepSeekBalanceThreshold
        return min(balance / threshold, 1.0)
    }

    var menuBarTopText: String {
        guard let snapshot = self.snapshot else { return "--" }
        return String(format: "%.2f", snapshot.todayCost)
    }

    var menuBarBottomText: String {
        guard let snapshot = self.snapshot else { return "--" }
        return String(format: "%.2f", snapshot.balance)
    }

    var menuBarCenterSymbol: CenterSymbol? {
        guard let snapshot = self.snapshot else { return nil }
        let threshold = AppSettings.deepSeekBalanceThreshold
        let warnAt = threshold * 0.1
        return snapshot.balance > warnAt ? .checkmark : .exclamation
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
        Task {
            await self.refresh()
        }
    }

    // MARK: - Refresh

    private func refresh() async {
        let token = AppSettings.deepSeekBearerToken
        guard !token.isEmpty else {
            self.scheduledResetRefreshTask?.cancel()
            self.errorMessage = "No DeepSeek token configured."
            return
        }

        guard !self.isRefreshing else { return }

        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let snap = try await self.service.fetchSnapshot()
            self.snapshot = snap
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
