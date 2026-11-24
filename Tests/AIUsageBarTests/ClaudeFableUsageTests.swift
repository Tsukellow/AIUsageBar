import XCTest
@testable import AIUsageBar

final class ClaudeFableUsageTests: XCTestCase {
    func testFableWeeklyScopedLimitIsMapped() async throws {
        let response = try Self.decodeResponse(limits: [
            Self.limit(kind: "weekly_all", percent: 12, modelName: nil),
            Self.limit(kind: "weekly_scoped", percent: 37, modelName: "Fable"),
        ])
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertEqual(snapshot.fableWeekly?.utilization, 37)
        XCTAssertEqual(snapshot.fableWeekly?.remainingPercent, 63)
        XCTAssertEqual(
            snapshot.fableWeekly?.resetsAt,
            Self.parseDate("2026-08-07T15:59:59.602060+00:00")
        )
        XCTAssertTrue(snapshot.resetDates.contains(snapshot.fableWeekly?.resetsAt))
    }

    func testUnrelatedWeeklyScopedLimitIsIgnored() async throws {
        let response = try Self.decodeResponse(limits: [
            Self.limit(kind: "weekly_scoped", percent: 44, modelName: "Sonnet"),
        ])
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertNil(snapshot.fableWeekly)
    }

    func testFableLimitWithWrongKindIsIgnored() async throws {
        let response = try Self.decodeResponse(limits: [
            Self.limit(kind: "weekly_all", percent: 21, modelName: "Fable"),
        ])
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertNil(snapshot.fableWeekly)
    }

    private static func decodeResponse(
        limits: [[String: Any]]
    ) throws -> ClaudeUsageResponse {
        let data = try JSONSerialization.data(withJSONObject: ["limits": limits])
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
    }

    private static func limit(
        kind: String,
        percent: Double,
        modelName: String?
    ) -> [String: Any] {
        var scope: [String: Any] = [:]
        if let modelName {
            scope["model"] = ["display_name": modelName]
        }
        return [
            "kind": kind,
            "percent": percent,
            "resets_at": "2026-08-07T15:59:59.602060+00:00",
            "scope": scope,
        ]
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
