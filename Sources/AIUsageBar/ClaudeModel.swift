import Foundation
import SwiftUI

@MainActor
final class ClaudeModel: ObservableObject {
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    @Published var isEnabled: Bool {
        didSet {
            AppSettings.claudeEnabled = self.isEnabled
            if !self.isEnabled && !AppSettings.codexEnabled {
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

    private let service = ClaudeUsageService()
    private let initialRefreshDelaySeconds: Double
    private let initialRefreshDueAt: Date
    private var refreshTask: Task<Void, Never>?
    private var scheduledResetRefreshTask: Task<Void, Never>?

    init() {
        self.initialRefreshDelaySeconds = AppSettings.initialRefreshDelaySeconds
        self.initialRefreshDueAt = Date().addingTimeInterval(self.initialRefreshDelaySeconds)
        self.isEnabled = AppSettings.claudeEnabled
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

    var menuBarFiveHourRemainingPercent: Double? {
        guard let remaining = self.snapshot?.fiveHour?.remainingPercent else {
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
        guard let remaining = self.snapshot?.sevenDay?.remainingPercent else {
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
              !AppSettings.claudeSessionCookie.isEmpty,
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

    private func refresh() async {
        let cookie = AppSettings.claudeSessionCookie
        guard !cookie.isEmpty else {
            self.scheduledResetRefreshTask?.cancel()
            self.errorMessage = "No Claude cookie configured."
            return
        }

        guard !self.isRefreshing else { return }

        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let snap = try await self.service.fetchSnapshot()
            self.snapshot = snap
            self.scheduleResetRefresh(from: snap)
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func scheduleResetRefresh(from snapshot: ClaudeUsageSnapshot?) {
        self.scheduledResetRefreshTask?.cancel()
        self.scheduledResetRefreshTask = UsageRefreshScheduler.scheduleResetRefresh(
            from: snapshot
        ) { [weak self] in
            await self?.refresh()
        }
    }
}
