import AppKit
import XCTest
@testable import AIUsageBar

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testDefaultWindowFitsSidebarAndCanBeResized() throws {
        _ = NSApplication.shared
        let content = SettingsView(model: AppModel(), claudeModel: ClaudeModel(), deepSeekModel: DeepSeekModel(),
                                   antigravityModel: AntigravityModel(), grokModel: GrokModel())
        let window = AppDelegate.makeSettingsWindow(content: content)
        defer { window.close() }
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.frame.size.width, 740, accuracy: 1)
        XCTAssertEqual(view.frame.size.height, 670, accuracy: 1)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 700, height: 420))

        window.setContentSize(window.contentMinSize)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size.width, 700, accuracy: 1)
        XCTAssertEqual(view.frame.size.height, 420, accuracy: 1)

        window.setContentSize(NSSize(width: 800, height: 680))
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size.width, 800, accuracy: 1)
        XCTAssertEqual(view.frame.size.height, 680, accuracy: 1)
    }
}
