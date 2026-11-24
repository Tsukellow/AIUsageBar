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
        XCTAssertEqual(ProviderID.antigravity.ringColor(in: defaults).toHex(), "#96CCFF")
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#9298A3")
        defaults.set("#777777", forKey: ProviderID.grok.ringColorKey)
        defaults.set("#EEDDEE", forKey: "deepSeekRingColorHex")
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#777777")
        XCTAssertEqual(ProviderID.deepSeek.ringColor(in: defaults).toHex(), "#EEDDEE")
        XCTAssertEqual(ProviderID.antigravity.ringColor(in: defaults).toHex(), "#96CCFF")

        defaults.set("", forKey: ProviderID.grok.ringColorKey)
        XCTAssertEqual(ProviderID.grok.ringColor(in: defaults).toHex(), "#9298A3")
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
        let providers = ProviderID.allCases
        XCTAssertEqual(Set(providers.map(\.defaultRingColorHex)).count, providers.count)
        for provider in providers {
            let mark = luminance(provider.ringColor(override: nil))
            XCTAssertGreaterThan((mark + 0.05) / (dark + 0.05), 4.5, provider.displayName)
        }
    }
}
