import Foundation
import XCTest
@testable import AIUsageBar

final class DeepSeekBalanceSettingsTests: XCTestCase {
    func testWarningIncludesTheBoundaryAndClampsTheRing() {
        let settings = DeepSeekBalanceSettings(fullBalance: 100, warningPercent: 5)
        XCTAssertEqual(settings.warningAmount, 5)
        XCTAssertTrue(settings.isLowBalance(5))
        XCTAssertTrue(settings.isLowBalance(4.99))
        XCTAssertFalse(settings.isLowBalance(5.01))
        XCTAssertTrue(settings.isLowBalance(0))
        XCTAssertTrue(settings.isLowBalance(-1))
        XCTAssertEqual(settings.ringFraction(for: -1), 0)
        XCTAssertEqual(settings.ringFraction(for: 25), 0.25)
        XCTAssertEqual(settings.ringFraction(for: 100), 1)
        XCTAssertEqual(settings.ringFraction(for: 200), 1)
    }

    func testSmallAmountsAndFractionalYuanBoundary() {
        let smallest = DeepSeekBalanceSettings(fullBalance: 5, warningPercent: 1)
        XCTAssertEqual(smallest.warningAmount, 0.05, accuracy: 0.000001)
        XCTAssertTrue(smallest.isLowBalance(0.05))
        XCTAssertFalse(smallest.isLowBalance(0.06))
        let fractional = DeepSeekBalanceSettings(fullBalance: 30, warningPercent: 3)
        XCTAssertTrue(fractional.isLowBalance(0.90))
        XCTAssertFalse(fractional.isLowBalance(0.91))
    }

    func testSliderPositionsSelectNonlinearPresets() {
        let amounts = PresetValueScale(presets: DeepSeekBalanceSettings.balancePresets, currentValue: 50)
        XCTAssertEqual(amounts.value(at: 0), 5)
        XCTAssertEqual(amounts.value(at: 4), 50)
        XCTAssertEqual(amounts.value(at: 7), 500)
        XCTAssertEqual(amounts.value(at: 8), 1000)
        XCTAssertEqual(amounts.value(at: -1), 5)
        XCTAssertEqual(amounts.value(at: 100), 1000)
        let percentages = PresetValueScale(presets: DeepSeekBalanceSettings.warningPresets, currentValue: 10)
        XCTAssertEqual(percentages.value(at: 4), 5)
        XCTAssertEqual(percentages.value(at: 5), 10)
        XCTAssertEqual(percentages.value(at: 6), 20)
    }

    func testLegacyAmountRemainsAnExactStableOption() {
        let scale = PresetValueScale(presets: DeepSeekBalanceSettings.balancePresets, currentValue: 80)
        XCTAssertEqual(scale.value(at: scale.index(for: 80)), 80)
        XCTAssertEqual(scale.value(at: scale.index(for: 80) + 1), 100)
        XCTAssertEqual(scale.value(at: scale.index(for: 80) - 1), 50)
        XCTAssertEqual(scale.values.filter { $0 == 80 }.count, 1)
        XCTAssertEqual(DeepSeekBalanceSettings(fullBalance: 80, warningPercent: 10).warningAmount, 8)
    }

    func testDefaultsUpgradeAndPersistenceInIsolatedDomain() throws {
        let name = "AIUsageBarTests.balance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppSettings.deepSeekBalanceSettings(in: defaults),
                       DeepSeekBalanceSettings(fullBalance: 50, warningPercent: 10))
        defaults.set(80.0, forKey: AppSettings.deepSeekBalanceThresholdKey)
        XCTAssertEqual(AppSettings.deepSeekBalanceSettings(in: defaults),
                       DeepSeekBalanceSettings(fullBalance: 80, warningPercent: 10))
        XCTAssertNil(defaults.object(forKey: AppSettings.deepSeekWarningPercentKey))
        defaults.set(3.0, forKey: AppSettings.deepSeekWarningPercentKey)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertEqual(AppSettings.deepSeekBalanceSettings(in: reopened),
                       DeepSeekBalanceSettings(fullBalance: 80, warningPercent: 3))
    }

    func testInvalidSettingsFallBackToFiniteDefaults() {
        for invalid in [0.0, -1, Double.nan, Double.infinity] {
            let settings = DeepSeekBalanceSettings(fullBalance: invalid, warningPercent: invalid)
            XCTAssertEqual(settings.fullBalance, 50)
            XCTAssertEqual(settings.warningPercent, 10)
        }
        XCTAssertEqual(DeepSeekBalanceSettings(fullBalance: 50, warningPercent: 101).warningPercent, 10)
    }
}
