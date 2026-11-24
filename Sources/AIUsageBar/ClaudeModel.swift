import Foundation
import SwiftUI

@MainActor
final class ClaudeModel: ObservableObject {
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    @Published var isEnabled: Bool {
        didSet {
            guard self.isEnabled != oldValue else { return }
            AppSettings.claudeEnabled = self.isEnabled
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
    private let refreshWork = ProviderRefreshWork()
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
        _ = self.requestRefresh()
    }

    private func requestRefresh() -> Task<Void, Never>? {
        guard self.isEnabled else { return nil }
        return self.refreshWork.start { [weak self] generation in
            await self?.refresh(generation: generation)
        }
    }

    private func refresh(generation: Int) async {
        let cookie = AppSettings.claudeSessionCookie
        guard !cookie.isEmpty else {
            self.scheduledResetRefreshTask?.cancel()
            self.errorMessage = "No Claude cookie configured."
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
            self.scheduleResetRefresh(from: snap)
            self.errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == self.refreshWork.generation else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    private func scheduleResetRefresh(from snapshot: ClaudeUsageSnapshot?) {
        self.scheduledResetRefreshTask?.cancel()
        self.scheduledResetRefreshTask = UsageRefreshScheduler.scheduleResetRefresh(
            from: snapshot
        ) { [weak self] in
            await self?.requestRefresh()?.value
        }
    }
}
