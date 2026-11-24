import XCTest
@testable import AIUsageBar

final class ProviderTrackingEnablementTests: XCTestCase {
    func testOnlyMenuBarAndMenuProvidersProduceStatusMeters() throws {
        let suite = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let enabled = Set(ProviderID.allCases)
        XCTAssertEqual(ProviderID.allCases.map(\.displayName), ["Claude", "Codex", "Antigravity", "Grok", "DeepSeek"])
        XCTAssertEqual(ProviderDisplay.menuBarProviders(enabled: enabled, in: defaults), [.claude, .codex, .antigravity, .grok, .deepSeek])
        defaults.set(ProviderDisplay.menuOnly.rawValue, forKey: AppSettings.displayKey(for: .codex))
        XCTAssertEqual(ProviderDisplay.menuBarProviders(enabled: enabled.subtracting([.grok]), in: defaults), [.claude, .antigravity, .deepSeek])

        for id in ProviderID.allCases {
            defaults.set(ProviderDisplay.menuOnly.rawValue, forKey: AppSettings.displayKey(for: id))
        }
        XCTAssertEqual(ProviderDisplay.menuBarProviders(enabled: enabled, in: defaults), [])
        defaults.set(ProviderDisplay.menuBarAndMenu.rawValue, forKey: AppSettings.displayKey(for: .grok))
        XCTAssertEqual(ProviderDisplay.menuBarProviders(enabled: enabled, in: defaults), [.grok])
        XCTAssertEqual(ProviderDisplay.menuBarProviders(enabled: [], in: defaults), [])
    }

    @MainActor
    func testLastProviderCanBeTurnedOff() {
        let previousClaude = AppSettings.claudeEnabled
        let previousCodex = AppSettings.codexEnabled
        let previousDeepSeek = AppSettings.deepSeekEnabled
        defer {
            AppSettings.claudeEnabled = previousClaude
            AppSettings.codexEnabled = previousCodex
            AppSettings.deepSeekEnabled = previousDeepSeek
        }
        AppSettings.claudeEnabled = false
        AppSettings.codexEnabled = false
        AppSettings.deepSeekEnabled = true
        let model = DeepSeekModel()
        model.isEnabled = false
        model.refreshNow()
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(AppSettings.deepSeekEnabled)
        XCTAssertFalse(model.isRefreshing)
    }

    @MainActor
    func testCancellationInvalidatesARequestBeforeNewWork() async {
        let work = ProviderRefreshWork()
        var previousGeneration: Int?
        var lateGenerationWouldPublish = false
        let old = work.start { generation in
            previousGeneration = generation
            try? await Task.sleep(for: .seconds(60))
            lateGenerationWouldPublish = generation == work.generation
        }
        while previousGeneration == nil { await Task.yield() }
        work.cancel()
        var latestGeneration: Int?
        await work.start { generation in latestGeneration = generation }?.value
        await old?.value
        XCTAssertFalse(lateGenerationWouldPublish)
        XCTAssertNotEqual(previousGeneration, latestGeneration)
    }
    @MainActor
    func testCodexCanBeDisabledWhenDeepSeekRemainsEnabled() {
        let previousClaude = AppSettings.claudeEnabled
        let previousCodex = AppSettings.codexEnabled
        let previousDeepSeek = AppSettings.deepSeekEnabled
        defer {
            AppSettings.claudeEnabled = previousClaude
            AppSettings.codexEnabled = previousCodex
            AppSettings.deepSeekEnabled = previousDeepSeek
        }

        AppSettings.claudeEnabled = false
        AppSettings.codexEnabled = true
        AppSettings.deepSeekEnabled = true

        let model = AppModel()
        model.isEnabled = false

        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(AppSettings.codexEnabled)
    }

    @MainActor
    func testClaudeCanBeDisabledWhenDeepSeekRemainsEnabled() {
        let previousClaude = AppSettings.claudeEnabled
        let previousCodex = AppSettings.codexEnabled
        let previousDeepSeek = AppSettings.deepSeekEnabled
        defer {
            AppSettings.claudeEnabled = previousClaude
            AppSettings.codexEnabled = previousCodex
            AppSettings.deepSeekEnabled = previousDeepSeek
        }

        AppSettings.claudeEnabled = true
        AppSettings.codexEnabled = false
        AppSettings.deepSeekEnabled = true

        let model = ClaudeModel()
        model.isEnabled = false

        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(AppSettings.claudeEnabled)
    }
}
