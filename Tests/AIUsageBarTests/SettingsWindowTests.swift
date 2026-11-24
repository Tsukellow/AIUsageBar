import AppKit
import SwiftUI
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

    @MainActor
    func testRowsAlignControlsOfDifferentWidthsAtTheTrailingInset() throws {
        _ = NSApplication.shared
        let toggle = NSView()
        let picker = NSView()
        let statusAction = NSView()
        let content = VStack {
            SettingsControlRow {
                Text("Show numbers in the menu bar")
            } control: {
                LayoutProbe(view: toggle).frame(width: 40, height: 20)
            }
            SettingsControlRow {
                Text("Show usage in")
            } control: {
                LayoutProbe(view: picker).frame(width: 185, height: 20)
            }
            SettingsControlRow {
                Text("A long status message can wrap without pushing the refresh button out of the row.")
            } control: {
                LayoutProbe(view: statusAction).frame(width: 100, height: 20)
            }
        }
        .padding(.horizontal, 16)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 503, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: content)
        window.contentView = host

        for width in [503.0, 600.0] {
            window.setContentSize(NSSize(width: width, height: 200))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.bounds.width, width, accuracy: 1)
            for probe in [toggle, picker, statusAction] {
                _ = try XCTUnwrap(probe.superview)
                XCTAssertEqual(probe.convert(probe.bounds, to: host).maxX, width - 16, accuracy: 1)
            }
        }
    }
}

private struct LayoutProbe: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { self.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
