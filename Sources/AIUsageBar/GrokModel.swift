import Foundation
import SwiftUI

@MainActor
final class GrokModel: ObservableObject {
    @Published private(set) var snapshot: GrokUsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var isEnabled: Bool {
        didSet {
            guard self.isEnabled != oldValue else { return }
            UserDefaults.standard.set(self.isEnabled, forKey: AppSettings.grokEnabledKey)
            self.stop()
            if self.isEnabled {
                self.startLoop()
                self.refreshNow()
            }
        }
    }

    private let work = ProviderRefreshWork()
    private var loop: Task<Void, Never>?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: AppSettings.grokEnabledKey)
        if self.isEnabled { self.startLoop() }
    }

    deinit { self.loop?.cancel() }

    var executablePath: String {
        UserDefaults.standard.string(forKey: AppSettings.grokExecutableKey) ?? ""
    }

    func setExecutablePath(_ path: String) {
        guard self.executablePath != path else { return }
        UserDefaults.standard.set(path, forKey: AppSettings.grokExecutableKey)
        self.work.cancel()
        self.snapshot = nil
        self.errorMessage = nil
        self.isRefreshing = false
        self.refreshNow()
    }

    func refreshNow() { _ = self.requestRefresh() }

    private func startLoop() {
        self.loop = UsageRefreshScheduler.startRefreshLoop(
            initialDelaySeconds: AppSettings.initialRefreshDelaySeconds,
            refreshIntervalSeconds: { AppSettings.refreshIntervalSeconds }
        ) { [weak self] in
            await self?.requestRefresh()?.value
        }
    }

    private func stop() {
        self.loop?.cancel()
        self.loop = nil
        self.work.cancel()
        self.isRefreshing = false
        self.snapshot = nil
        self.errorMessage = nil
    }

    private func requestRefresh() -> Task<Void, Never>? {
        guard self.isEnabled else { return nil }
        return self.work.start { [weak self] generation in
            await self?.refresh(generation: generation)
        }
    }

    private func refresh(generation: Int) async {
        self.isRefreshing = true
        defer { if generation == self.work.generation { self.isRefreshing = false } }
        do {
            guard let url = self.resolveExecutable() else { throw GrokBillingError.missingCLI }
            let snapshot = try await GrokBillingCommand(executable: url).run()
            guard !Task.isCancelled, generation == self.work.generation else { return }
            self.snapshot = snapshot
            self.errorMessage = nil
        } catch {
            guard !Task.isCancelled, generation == self.work.generation else { return }
            // The CLI reply has no stable account ID. Never carry a previous reading over a failure.
            self.snapshot = nil
            self.errorMessage = error.localizedDescription
        }
    }

    private func resolveExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = self.executablePath.isEmpty
            ? [home + "/.local/bin/grok", "/opt/homebrew/bin/grok", "/usr/local/bin/grok"]
            : [self.executablePath]
        return candidates.first { path in
            var isDirectory: ObjCBool = false
            return path.hasPrefix("/") && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }.map { URL(fileURLWithPath: $0) }
    }
}
