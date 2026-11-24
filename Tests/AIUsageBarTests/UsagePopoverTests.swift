import AppKit
import SwiftUI
import XCTest
@testable import AIUsageBar

final class UsagePopoverTests: XCTestCase {
    @MainActor
    func testPopoverFitsItsContentOnOpenAndWhenRowsChange() async throws {
        _ = NSApplication.shared
        let rows = PopoverRows()
        let popover = AppDelegate.makeUsagePopover(content: PopoverRowsView(rows: rows))
        popover.animates = false
        XCTAssertEqual(popover.contentSize.width, 300)
        XCTAssertEqual(popover.contentSize.height, 56)

        let anchorWindow = NSWindow(contentRect: NSRect(x: 120, y: 280, width: 32, height: 32),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        defer {
            popover.close()
            anchorWindow.close()
        }
        let anchor = try XCTUnwrap(anchorWindow.contentView)
        anchorWindow.orderFrontRegardless()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        XCTAssertTrue(popover.isShown)

        rows.count = 20
        try await self.waitForHeight(560, popover: popover)
        rows.count = 3
        try await self.waitForHeight(84, popover: popover)
    }

    @MainActor
    private func waitForHeight(_ height: CGFloat, popover: NSPopover) async throws {
        for _ in 0..<60 {
            if popover.contentSize.height == height { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(popover.contentSize.height, height)
    }
}

@MainActor
private final class PopoverRows: ObservableObject {
    @Published var count = 2
}

private struct PopoverRowsView: View {
    @ObservedObject var rows: PopoverRows

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<self.rows.count, id: \.self) { index in
                Text("Quota row \(index)").frame(height: 28)
            }
        }
    }
}
