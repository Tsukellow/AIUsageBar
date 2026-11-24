import AppKit
import XCTest
@testable import AIUsageBar

final class ProviderAppearanceTests: XCTestCase {
    func testRingDefaultsAndExplicitOverridesAreIndependent() throws {
        let suite = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ProviderID.allCases.map(\.ringColorKey),
                       ["claudeRingColorHex", "codexRingColorHex", "geminiRingColorHex", "grokRingColorHex", "deepSeekRingColorHex"])
        XCTAssertEqual(ProviderID.antigravity.ringColor(in: defaults).toHex(), "#CDB0FF")
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#BFC1C6")
        defaults.set("#777777", forKey: ProviderID.grok.ringColorKey)
        defaults.set("#EEDDEE", forKey: "deepSeekRingColorHex")
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#777777")
        XCTAssertEqual(ProviderID.deepSeek.ringColor(in: defaults).toHex(), "#EEDDEE")
        XCTAssertEqual(ProviderID.antigravity.ringColor(in: defaults).toHex(), "#CDB0FF")

        defaults.set("", forKey: ProviderID.grok.ringColorKey)
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#BFC1C6")
    }

    func testDefaultPaletteIsDistinctAndVisibleOnDarkBackground() {
        func luminance(_ color: NSColor) -> Double {
            func linear(_ channel: CGFloat) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
        }

        let dark = luminance(NSColor(hex: "#202124")!)
        let palette = ProviderID.allCases.map { ($0.displayName, $0.ringAppearance) }
            + [("Antigravity Claude & GPT", RingAppearance.antigravityThirdParty)]
        XCTAssertEqual(Set(palette.map { $0.1.defaultHex }).count, palette.count)
        for (name, appearance) in palette {
            let mark = luminance(appearance.color(override: nil))
            XCTAssertGreaterThan((mark + 0.05) / (dark + 0.05), 4.5, name)
        }
    }

    func testAntigravityPoolColorsCanBeSetAndRestoredIndependently() throws {
        let suite = "AIUsageBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let gemini = ProviderID.antigravity.ringAppearance
        let partner = RingAppearance.antigravityThirdParty
        XCTAssertNotEqual(gemini.key, partner.key)
        XCTAssertEqual(partner.color(in: defaults).toHex(), "#CF8AC6")
        defaults.set("#11AABB", forKey: gemini.key)
        defaults.set("#AABB11", forKey: partner.key)
        XCTAssertEqual(gemini.color(in: defaults).toHex(), "#11AABB")
        XCTAssertEqual(partner.color(in: defaults).toHex(), "#AABB11")
        defaults.set("", forKey: partner.key)
        XCTAssertEqual(partner.color(in: defaults).toHex(), "#CF8AC6")
        XCTAssertEqual(gemini.color(in: defaults).toHex(), "#11AABB")
    }
}
