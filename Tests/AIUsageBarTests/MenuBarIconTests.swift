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
        XCTAssertEqual(missing.topText, "--%")
        XCTAssertEqual(missing.bottomText, "--%")
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

        let withNumbers = MenuBarIconView(services: [stale], showsNumbers: true).renderedImage()
        let withoutNumbers = MenuBarIconView(services: [stale], showsNumbers: false).renderedImage()
        XCTAssertEqual(withNumbers.size, NSSize(width: 18, height: 22))
        XCTAssertEqual(try XCTUnwrap(withNumbers.tiffRepresentation), try XCTUnwrap(withoutNumbers.tiffRepresentation))
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
