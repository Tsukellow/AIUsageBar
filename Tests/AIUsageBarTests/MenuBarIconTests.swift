import AppKit
import XCTest
@testable import AIUsageBar

final class MenuBarIconTests: XCTestCase {
    func testNumbersAreOnByDefaultAndCanBeTurnedOff() throws {
        let name = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertTrue(AppSettings.showMenuBarNumbers(in: defaults))
        defaults.set(false, forKey: AppSettings.showMenuBarNumbersKey)
        XCTAssertFalse(AppSettings.showMenuBarNumbers(in: defaults))
        defaults.set(true, forKey: AppSettings.showMenuBarNumbersKey)
        XCTAssertTrue(AppSettings.showMenuBarNumbers(in: defaults))
    }

    @MainActor
    func testCodexOmitsTheFiveHourLabelOnlyWhenWeeklyQuotaWasReported() {
        func icon(fiveHour: Double?, weekly: Double?) -> ServiceIconData {
            let limits = RateLimitSnapshot(fiveHourRemainingPercent: fiveHour, fiveHourResetsAt: nil,
                                           weeklyRemainingPercent: weekly, weeklyResetsAt: nil,
                                           creditsRemaining: nil, sourceLabel: "Test")
            return ServiceIconData.codex(rateLimits: limits, ringColor: .white)
        }

        let weeklyOnly = icon(fiveHour: nil, weekly: 74)
        XCTAssertTrue(weeklyOnly.topText.isEmpty)
        XCTAssertEqual(weeklyOnly.bottomText, "74%")
        XCTAssertEqual(weeklyOnly.ringFraction, 0.74, accuracy: 0.001)

        let both = icon(fiveHour: 0, weekly: 74)
        XCTAssertEqual(both.topText, "0%")
        XCTAssertEqual(both.bottomText, "74%")
        XCTAssertEqual(both.ringFraction, 0)

        let missing = ServiceIconData.codex(rateLimits: nil, ringColor: .white)
        XCTAssertEqual(missing.centerSymbol, .questionMark)
        let missingWeekly = icon(fiveHour: 59, weekly: nil)
        XCTAssertEqual(missingWeekly.centerSymbol, .questionMark)
        XCTAssertTrue(missingWeekly.topText.isEmpty)
        XCTAssertTrue(missingWeekly.bottomText.isEmpty)
        XCTAssertEqual(missingWeekly.ringFraction, 0)
    }

    @MainActor
    func testSingleNumberIsCenteredInEitherTextStyle() throws {
        let variants = [
            ServiceIconData(ringFraction: 0.74, topText: "74%", bottomText: "", ringColor: .white),
            ServiceIconData(ringFraction: 0.74, topText: "", bottomText: "74%", ringColor: .white),
        ]

        for service in variants {
            let icon = MenuBarIconView(services: [service], showsNumbers: true).renderedImage()
            let data = try XCTUnwrap(icon.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            let firstTextColumn = Int((22 / icon.size.width) * CGFloat(bitmap.pixelsWide))
            let textRows = (0..<bitmap.pixelsHigh).filter { y in
                (firstTextColumn..<bitmap.pixelsWide).contains { x in
                    (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15
                }
            }
            let top = try XCTUnwrap(textRows.first)
            let bottom = try XCTUnwrap(textRows.last)
            XCTAssertEqual(Double(top + bottom + 1) / Double(bitmap.pixelsHigh), 1, accuracy: 0.18)
        }
    }

    @MainActor
    func testStaleAntigravityUsesOnlyTheWarningRingEvenWhenNumbersAreOn() throws {
        let windows = AntigravityQuotaSnapshot.MenuWindows(
            fiveHours: SubscriptionWindow(title: "5 hours", remainingFraction: 0.6, resetsAt: nil),
            weekly: SubscriptionWindow(title: "Weekly", remainingFraction: 0.8, resetsAt: nil)
        )
        let fresh = ServiceIconData.antigravity(windows: windows, isStale: false, ringColor: .systemBlue)
        XCTAssertEqual(fresh.topText, "60%")
        XCTAssertEqual(fresh.bottomText, "80%")
        XCTAssertEqual(fresh.ringFraction, 0.6)
        XCTAssertNil(fresh.centerSymbol)

        let stale = ServiceIconData.antigravity(windows: windows, isStale: true, ringColor: .systemBlue)
        XCTAssertEqual(stale.ringFraction, 0)
        XCTAssertTrue(stale.topText.isEmpty)
        XCTAssertTrue(stale.bottomText.isEmpty)
        XCTAssertEqual(stale.centerSymbol, .exclamation)
        XCTAssertEqual(ServiceIconData.antigravity(windows: .init(), isStale: true, ringColor: nil).centerSymbol, .exclamation)

        let withNumbers = MenuBarIconView(services: [stale], showsNumbers: true).renderedImage()
        let withoutNumbers = MenuBarIconView(services: [stale], showsNumbers: false).renderedImage()
        XCTAssertEqual(withNumbers.size, NSSize(width: 18, height: 22))
        XCTAssertEqual(try XCTUnwrap(withNumbers.tiffRepresentation), try XCTUnwrap(withoutNumbers.tiffRepresentation))
    }

    @MainActor
    func testMissingDataUsesAQuestionMarkWithoutNumberSpace() throws {
        let week = SubscriptionWindow(title: "Weekly", remainingFraction: 0.8, resetsAt: nil)
        let settings = DeepSeekBalanceSettings(fullBalance: 50, warningPercent: 10)
        let variants: [ServiceIconData] = [
            .claude(fiveHour: nil, weekly: 80, ringColor: .systemOrange),
            .claude(fiveHour: 60, weekly: nil, ringColor: .systemOrange),
            .codex(rateLimits: nil, ringColor: .white),
            .antigravity(windows: .init(weekly: week), isStale: false, ringColor: .systemBlue),
            .antigravity(windows: .init(fiveHours: week), isStale: false, ringColor: .systemPurple),
            .grok(weekly: nil, ringColor: .systemGray),
            .deepSeek(balance: nil, todayCost: 1, settings: settings, ringColor: .systemBlue),
            .deepSeek(balance: 2.5, todayCost: nil, settings: settings, ringColor: .systemBlue),
        ]
        for icon in variants {
            XCTAssertEqual(icon.centerSymbol, .questionMark)
            XCTAssertEqual(icon.ringFraction, 0)
            XCTAssertTrue(icon.topText.isEmpty)
            XCTAssertTrue(icon.bottomText.isEmpty)
            XCTAssertEqual(MenuBarIconView(services: [icon], showsNumbers: true).renderedImage().size,
                           NSSize(width: 18, height: 22))
        }
        let unknown = MenuBarIconView(services: [variants[0]], showsNumbers: false).renderedImage()
        let ring = ServiceIconData(ringFraction: 0, topText: "", bottomText: "", ringColor: variants[0].ringColor)
        let empty = MenuBarIconView(services: [ring], showsNumbers: false).renderedImage()
        XCTAssertNotEqual(try XCTUnwrap(unknown.tiffRepresentation), try XCTUnwrap(empty.tiffRepresentation))
    }

    @MainActor
    func testReportedZeroRemainsAValidNumber() {
        let claude = ServiceIconData.claude(fiveHour: 0, weekly: 0, ringColor: nil)
        XCTAssertEqual(claude.topText, "0%")
        XCTAssertEqual(claude.bottomText, "0%")
        XCTAssertNil(claude.centerSymbol)

        let week = SubscriptionWindow(title: "Weekly", remainingFraction: 0, resetsAt: nil)
        let grok = ServiceIconData.grok(weekly: week, ringColor: nil)
        XCTAssertTrue(grok.topText.isEmpty)
        XCTAssertEqual(grok.bottomText, "0%")
        XCTAssertNil(grok.centerSymbol)

        let deepSeek = ServiceIconData.deepSeek(balance: 0, todayCost: 0,
                                              settings: DeepSeekBalanceSettings(fullBalance: 50, warningPercent: 10),
                                              ringColor: nil)
        XCTAssertEqual(deepSeek.topText, "0.00")
        XCTAssertEqual(deepSeek.bottomText, "0.00")
        XCTAssertEqual(deepSeek.centerSymbol, .exclamation)
    }

    @MainActor
    func testGrokAndCodexRenderTheSameWeeklyOnlyLabel() throws {
        let week = SubscriptionWindow(title: "Weekly", remainingFraction: 0.74, resetsAt: nil)
        let limits = RateLimitSnapshot(fiveHourRemainingPercent: nil, fiveHourResetsAt: nil,
                                       weeklyRemainingPercent: 74, weeklyResetsAt: nil,
                                       creditsRemaining: nil, sourceLabel: "Test")
        let grok = MenuBarIconView(services: [.grok(weekly: week, ringColor: .white)], showsNumbers: true).renderedImage()
        let codex = MenuBarIconView(services: [.codex(rateLimits: limits, ringColor: .white)], showsNumbers: true).renderedImage()
        XCTAssertEqual(grok.size, codex.size)
        XCTAssertEqual(try XCTUnwrap(grok.tiffRepresentation), try XCTUnwrap(codex.tiffRepresentation))
    }

    @MainActor
    func testBothQuotasAutomaticallyRenderDualRingsWithoutNumbers() throws {
        let base = ServiceIconData.claude(fiveHour: 35, weekly: 82, ringColor: .systemOrange)
        let lessWeekly = ServiceIconData.claude(fiveHour: 35, weekly: 42, ringColor: .systemOrange)
        let moreFiveHour = ServiceIconData.claude(fiveHour: 64, weekly: 82, ringColor: .systemOrange)
        func image(_ icon: ServiceIconData) -> NSImage {
            MenuBarIconView(services: [icon], showsNumbers: false).renderedImage()
        }

        let dual = image(base)
        XCTAssertEqual(dual.size, NSSize(width: 18, height: 22))
        let single = ServiceIconData(ringFraction: 0.35, topText: "", bottomText: "", ringColor: .systemOrange)
        XCTAssertEqual(image(single).size, dual.size)
        XCTAssertNotEqual(try XCTUnwrap(dual.tiffRepresentation), try XCTUnwrap(image(single).tiffRepresentation))
        XCTAssertNotEqual(try XCTUnwrap(dual.tiffRepresentation),
                          try XCTUnwrap(image(lessWeekly).tiffRepresentation))
        XCTAssertNotEqual(try XCTUnwrap(dual.tiffRepresentation),
                          try XCTUnwrap(image(moreFiveHour).tiffRepresentation))
    }

    @MainActor
    func testWeeklyOnlyCodexOmitsTheInnerRingButReportedZeroKeepsIt() throws {
        func icon(fiveHour: Double?) -> ServiceIconData {
            let limits = RateLimitSnapshot(fiveHourRemainingPercent: fiveHour, fiveHourResetsAt: nil,
                                           weeklyRemainingPercent: 74, weeklyResetsAt: nil,
                                           creditsRemaining: nil, sourceLabel: "Test")
            return .codex(rateLimits: limits, ringColor: .white)
        }
        let weeklyOnly = icon(fiveHour: nil)
        let exhausted = icon(fiveHour: 0)
        XCTAssertNil(weeklyOnly.quotaRings)
        XCTAssertEqual(exhausted.quotaRings, .init(fiveHour: 0, weekly: 0.74))
        let single = MenuBarIconView(services: [weeklyOnly], showsNumbers: false).renderedImage()
        let withEmptyInner = MenuBarIconView(services: [exhausted], showsNumbers: false).renderedImage()
        XCTAssertEqual(single.size, withEmptyInner.size)
        XCTAssertNotEqual(try XCTUnwrap(single.tiffRepresentation), try XCTUnwrap(withEmptyInner.tiffRepresentation))
    }

    @MainActor
    func testOnlyCompleteSupportedQuotaPairsUseDualRings() {
        let weekly = SubscriptionWindow(title: "Weekly", remainingFraction: 0.92, resetsAt: nil)
        let fiveHour = SubscriptionWindow(title: "5 hours", remainingFraction: 0.63, resetsAt: nil)
        let fresh = ServiceIconData.antigravity(windows: .init(fiveHours: fiveHour, weekly: weekly),
                                               isStale: false, ringColor: .systemBlue)
        XCTAssertEqual(fresh.quotaRings, .init(fiveHour: 0.63, weekly: 0.92))

        let variants: [ServiceIconData] = [
            .antigravity(windows: .init(fiveHours: fiveHour, weekly: weekly), isStale: true, ringColor: .systemBlue),
            .claude(fiveHour: nil, weekly: 82, ringColor: .systemOrange),
            .grok(weekly: weekly, ringColor: .systemGray),
            .deepSeek(balance: 2.50, todayCost: 1.28, settings: .init(fullBalance: 50, warningPercent: 10), ringColor: .systemBlue),
        ]
        for icon in variants {
            XCTAssertNil(icon.quotaRings)
        }
    }

    @MainActor
    func testRingsOnlyIgnoresTextAndUsesLessSpace() throws {
        let services = [
            ServiceIconData(ringFraction: 0.6, topText: "60%", bottomText: "90%", ringColor: .systemBlue),
            ServiceIconData(ringFraction: 0.1, topText: "¥12.50", bottomText: "¥3.20", ringColor: .systemTeal, centerSymbol: .exclamation),
        ]
        let otherText = services.map {
            ServiceIconData(ringFraction: $0.ringFraction, topText: "--%", bottomText: "0%",
                            ringColor: $0.ringColor, centerSymbol: $0.centerSymbol)
        }
        let rings = MenuBarIconView(services: services, showsNumbers: false).renderedImage()
        let otherRings = MenuBarIconView(services: otherText, showsNumbers: false).renderedImage()
        let numbers = MenuBarIconView(services: services, showsNumbers: true).renderedImage()

        XCTAssertEqual(rings.size, NSSize(width: 44, height: 22))
        XCTAssertGreaterThan(numbers.size.width, rings.size.width)
        XCTAssertEqual(try XCTUnwrap(rings.tiffRepresentation), try XCTUnwrap(otherRings.tiffRepresentation))
    }

    @MainActor
    func testRingsOnlyStillDrawsTheBalanceWarning() throws {
        let plain = ServiceIconData(ringFraction: 0.1, topText: "¥12.50", bottomText: "", ringColor: .systemTeal)
        let warning = ServiceIconData(ringFraction: 0.1, topText: "¥12.50", bottomText: "",
                                      ringColor: .systemTeal, centerSymbol: .exclamation)
        let plainImage = MenuBarIconView(services: [plain], showsNumbers: false).renderedImage()
        let warningImage = MenuBarIconView(services: [warning], showsNumbers: false).renderedImage()

        XCTAssertEqual(plainImage.size, warningImage.size)
        XCTAssertNotEqual(try XCTUnwrap(plainImage.tiffRepresentation), try XCTUnwrap(warningImage.tiffRepresentation))
    }
}
