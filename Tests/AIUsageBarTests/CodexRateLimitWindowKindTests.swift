import XCTest
@testable import AIUsageBar

final class CodexRateLimitWindowKindTests: XCTestCase {
    func testFiveHourWindowIsClassifiedByDuration() {
        XCTAssertEqual(
            CodexRateLimitWindowKind(durationSeconds: 18_000),
            .fiveHour
        )
    }

    func testWeeklyWindowIsClassifiedByDurationEvenWhenItIsPrimary() {
        XCTAssertEqual(
            CodexRateLimitWindowKind(durationSeconds: 604_800),
            .weekly
        )
    }

    func testUnknownWindowDurationIsNotMislabelled() {
        XCTAssertNil(CodexRateLimitWindowKind(durationSeconds: 86_400))
    }
}
