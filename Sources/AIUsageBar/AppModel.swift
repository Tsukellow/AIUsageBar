import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    @Published var isEnabled: Bool {
        didSet {
            AppSettings.codexEnabled = self.isEnabled
            if !self.isEnabled && !AppSettings.claudeEnabled {
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

    let loginManager = LaunchAtLoginManager()

    private let service = CodexUsageService()
    private let initialRefreshDelaySeconds: Double
    private let initialRefreshDueAt: Date
    private var refreshTask: Task<Void, Never>?
    private var scheduledResetRefreshTask: Task<Void, Never>?

    init() {
        self.initialRefreshDelaySeconds = AppSettings.initialRefreshDelaySeconds
        self.initialRefreshDueAt = Date().addingTimeInterval(self.initialRefreshDelaySeconds)
        self.isEnabled = AppSettings.codexEnabled
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

    var menuBarFiveHourRemainingPercent: Double? {
        guard let remaining = self.snapshot?.rateLimits?.fiveHourRemainingPercent else {
            return nil
        }
        return min(100, max(0, remaining))
    }

    var menuBarFiveHourRemainingText: String {
        guard let remaining = self.menuBarFiveHourRemainingPercent else {
            return "--%"
        }
        return "\(Int(remaining.rounded()))%"
    }

    var menuBarWeeklyRemainingPercent: Double? {
        guard let remaining = self.snapshot?.rateLimits?.weeklyRemainingPercent else {
            return nil
        }
        return min(100, max(0, remaining))
    }

    var menuBarWeeklyRemainingText: String {
        guard let remaining = self.menuBarWeeklyRemainingPercent else {
            return "--%"
        }
        return "\(Int(remaining.rounded()))%"
    }

    var menuBarFiveHourRemainingFraction: Double {
        guard let remaining = self.menuBarFiveHourRemainingPercent else {
            return 0
        }
        return remaining / 100
    }

    var pendingInitialRefreshDueAt: Date? {
        guard self.snapshot == nil,
              !self.isRefreshing,
              self.errorMessage == nil,
              Date() < self.initialRefreshDueAt else {
            return nil
        }
        return self.initialRefreshDueAt
    }

    func refreshNow() {
        Task {
            await self.refresh()
        }
    }

    private func refresh() async {
        guard !self.isRefreshing else {
            return
        }

        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let snapshot = try await self.service.fetchSnapshot()
            self.snapshot = snapshot
            self.scheduleResetRefresh(from: snapshot)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func scheduleResetRefresh(from snapshot: UsageSnapshot?) {
        self.scheduledResetRefreshTask?.cancel()
        self.scheduledResetRefreshTask = UsageRefreshScheduler.scheduleResetRefresh(
            from: snapshot
        ) { [weak self] in
            await self?.refresh()
        }
    }
}
