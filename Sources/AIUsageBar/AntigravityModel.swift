import Foundation
import SwiftUI

@MainActor
final class AntigravityModel: ObservableObject {
    @Published private(set) var snapshot: AntigravityQuotaSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isStale = false
    @Published private(set) var menuGemini = AntigravityQuotaSnapshot.MenuWindows()
    @Published private(set) var menuThirdParty = AntigravityQuotaSnapshot.MenuWindows()
    @Published var isEnabled: Bool {
        didSet {
            guard self.isEnabled != oldValue else { return }
            UserDefaults.standard.set(self.isEnabled, forKey: AppSettings.antigravityEnabledKey)
            if self.isEnabled { self.start() } else { self.stop() }
        }
    }

    private let statusLine = AntigravityStatusLine()
    private var loop: Task<Void, Never>?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: AppSettings.antigravityEnabledKey)
        if self.isEnabled { self.start() }
    }

    deinit { self.loop?.cancel() }

    func connect() {
        guard self.isEnabled else { return }
        do {
            try self.statusLine.connect()
            self.errorMessage = nil
            self.refreshNow()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func refreshNow() {
        guard self.isEnabled else { return }
        let snapshot = self.statusLine.readSnapshot()
        let now = Date.now
        let stale = snapshot?.isStale(at: now) ?? false
        let gemini = snapshot?.menuWindows(for: .gemini, at: now) ?? .init()
        let thirdParty = snapshot?.menuWindows(for: .thirdParty, at: now) ?? .init()
        if self.snapshot != snapshot { self.snapshot = snapshot }
        if self.isStale != stale { self.isStale = stale }
        if self.menuGemini != gemini { self.menuGemini = gemini }
        if self.menuThirdParty != thirdParty { self.menuThirdParty = thirdParty }
    }

    private func start() {
        self.loop = UsageRefreshScheduler.startRefreshLoop(
            initialDelaySeconds: 0,
            refreshIntervalSeconds: { AppSettings.refreshIntervalSeconds }
        ) { [weak self] in
            self?.refreshNow()
        }
    }

    private func stop() {
        self.loop?.cancel()
        self.loop = nil
        self.statusLine.clearSnapshot()
        self.snapshot = nil
        self.isStale = false
        self.menuGemini = .init()
        self.menuThirdParty = .init()
        self.errorMessage = nil
    }
}
