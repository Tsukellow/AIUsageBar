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
