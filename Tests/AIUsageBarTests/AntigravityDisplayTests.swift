import Foundation
import XCTest
@testable import AIUsageBar

final class AntigravityDisplayTests: XCTestCase {
    func testClaudeGPTIsDropDownOnlyByDefaultAndEachSettingControlsBothSurfaces() throws {
        let suite = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = try XCTUnwrap(AntigravityQuotaSnapshot.capture(Data(#"""
        {"quota":{"gemini-5h":{"remaining_fraction":0.6},
                  "3p-weekly":{"remaining_fraction":0.9},
                  "gemini-argon-wtu-weekly":{"remaining_fraction":0.7}}}
        """#.utf8), at: .now))
        XCTAssertEqual(AppSettings.antigravityThirdPartyDisplay(in: defaults), .menuOnly)

        let enabled: Set<ProviderID> = [.codex, .antigravity, .grok]
        let normalMeters: [MenuBarMeter] = [.provider(.codex), .provider(.antigravity), .provider(.grok)]
        let modes: [AntigravityThirdPartyDisplay] = [.hidden, .menuOnly, .menuBarAndMenu]
        for mode in modes {
            defaults.set(mode.rawValue, forKey: AppSettings.antigravityThirdPartyDisplayKey)
            let saved = AppSettings.antigravityThirdPartyDisplay(in: defaults)
            XCTAssertEqual(saved, mode)
            XCTAssertEqual(snapshot.displayedPools(thirdPartyDisplay: saved),
                           mode == .hidden ? [.gemini, .argon] : [.gemini, .thirdParty, .argon])
            XCTAssertEqual(saved.showsPoolTitle(.gemini), mode != .hidden)
            XCTAssertTrue(saved.showsPoolTitle(.argon))
            XCTAssertEqual(
                MenuBarMeter.visibleMeters(enabled: enabled, hasAntigravityThirdPartyQuota: true, in: defaults),
                mode == .menuBarAndMenu ? [.provider(.codex), .provider(.antigravity), .antigravityThirdParty, .provider(.grok)] : normalMeters
            )
        }
    }

    func testClaudeGPTPlacementIsIndependentOfGeminiButRequiresTrackingAndQuota() throws {
        let suite = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AntigravityThirdPartyDisplay.menuBarAndMenu.rawValue, forKey: AppSettings.antigravityThirdPartyDisplayKey)
        defaults.set(ProviderDisplay.menuOnly.rawValue, forKey: AppSettings.displayKey(for: .antigravity))

        XCTAssertEqual(MenuBarMeter.visibleMeters(enabled: [.antigravity], hasAntigravityThirdPartyQuota: true, in: defaults),
                       [.antigravityThirdParty])
        XCTAssertEqual(MenuBarMeter.visibleMeters(enabled: [.antigravity], hasAntigravityThirdPartyQuota: false, in: defaults), [])
        XCTAssertEqual(MenuBarMeter.visibleMeters(enabled: [], hasAntigravityThirdPartyQuota: true, in: defaults), [])
    }
}
