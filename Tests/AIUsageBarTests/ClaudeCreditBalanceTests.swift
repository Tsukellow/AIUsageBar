import XCTest
@testable import AIUsageBar

final class ClaudeCreditBalanceTests: XCTestCase {
    func testPositiveSpendBalanceIsMappedForDisplay() async throws {
        let response = try Self.decodeResponse(balance: [
            "amount_minor": 1_234,
            "currency": "USD",
            "exponent": 2,
        ])
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertEqual(snapshot.creditBalance?.amountMinor, 1_234)
        XCTAssertEqual(snapshot.creditBalance?.currency, "USD")
        XCTAssertEqual(snapshot.creditBalance?.exponent, 2)
    }

    func testNullSpendBalanceIsNotMappedForDisplay() async throws {
        let response = try Self.decodeResponse(balance: NSNull())
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertNil(snapshot.creditBalance)
    }

    func testZeroSpendBalanceIsNotMappedForDisplay() async throws {
        let response = try Self.decodeResponse(balance: [
            "amount_minor": 0,
            "currency": "USD",
            "exponent": 2,
        ])
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertNil(snapshot.creditBalance)
    }

    func testUnexpectedSpendBalanceShapeDoesNotBreakUsageResponse() async throws {
        let response = try Self.decodeResponse(balance: "unknown")
        let service = ClaudeUsageService()

        let snapshot = await service.makeSnapshot(from: response)

        XCTAssertNil(snapshot.creditBalance)
    }

    private static func decodeResponse(balance: Any) throws -> ClaudeUsageResponse {
        let data = try JSONSerialization.data(withJSONObject: [
            "spend": [
                "balance": balance,
            ],
        ])
        return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
    }
}
