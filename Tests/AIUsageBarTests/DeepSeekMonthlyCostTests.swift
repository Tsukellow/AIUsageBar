import Foundation
import XCTest
@testable import AIUsageBar

final class DeepSeekMonthlyCostTests: XCTestCase {
    func testMonthlyCostComesFromCostEndpointTotalWhenSummaryOmitsLegacyField() async throws {
        let snapshot = try await self.snapshot(costData: [[
            "currency": "CNY",
            "total": [
                ["model": "deepseek-v4-pro", "usage": [
                    ["type": "PROMPT_CACHE_HIT_TOKEN", "amount": "1.25"],
                    ["type": "RESPONSE_TOKEN", "amount": 2.27279886],
                ]],
            ],
        ]])

        XCTAssertEqual(try XCTUnwrap(snapshot.monthlyCost), 3.52279886, accuracy: 0.000000001)
        XCTAssertNil(snapshot.todayCost)
        XCTAssertEqual(snapshot.cacheHitRate, 75, accuracy: 0.000000001)
    }

    func testCostFailureDoesNotEraseBalanceOrReportZero() async throws {
        let failures: [(Any, Int)] = [(NSNull(), 200), ([String: Any](), 503)]
        for (payload, status) in failures {
            let snapshot = try await self.snapshot(costData: payload, costStatus: status)
            XCTAssertNil(snapshot.todayCost)
            XCTAssertNil(snapshot.monthlyCost)
            XCTAssertEqual(snapshot.balance, 42)
            XCTAssertEqual(snapshot.cacheHitRate, 75)
        }
    }

    func testOnlyReportedAmountsAreSummed() throws {
        func decode(_ json: String) throws -> DeepSeekCostResponse {
            try JSONDecoder().decode(DeepSeekCostResponse.self, from: Data(json.utf8))
        }
        let zero = try decode(#"{"total":[{"usage":[{"amount":0},{"amount":"0.00"}]}]}"#)
        XCTAssertEqual(zero.monthlyCost, 0)
        XCTAssertNil(try decode(#"{"total":[],"days":[]}"#).monthlyCost)
        XCTAssertNil(try decode(#"{"total":[{"usage":[{"amount":"1.25"},{"amount":{"unexpected":1}}]}]}"#).monthlyCost)
        XCTAssertNil(try decode(#"{"total":[{"usage":[{"amount":"NaN"}]}]}"#).monthlyCost)

        let fromDays = try decode(#"""
        {"total":{"changedShape":true},"days":[
            {"date":"2026-11-24","data":[{"usage":[{"amount":0}]}]},
            {"date":"2026-11-23","data":[{"usage":[{"amount":2.25}]}]}
        ]}
        """#)
        XCTAssertEqual(fromDays.cost(on: "2026-11-24"), 0)
        XCTAssertNil(fromDays.cost(on: "2026-11-22"))
        XCTAssertEqual(fromDays.monthlyCost, 2.25)
    }

    private func snapshot(costData: Any, costStatus: Int = 200) async throws -> DeepSeekUsageSnapshot {
        let previousToken = AppSettings.deepSeekBearerToken
        AppSettings.deepSeekBearerToken = "test-token"
        defer { AppSettings.deepSeekBearerToken = previousToken }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        MockDeepSeekURLProtocol.requestHandler = { request in
            let body: Any
            let path = request.url?.path
            switch path {
            case "/api/v0/users/get_user_summary":
                body = [
                    "code": 0,
                    "data": [
                        "biz_code": 0,
                        "biz_data": [
                            "normal_wallets": [["balance": "42.00"]],
                            "bonus_wallets": [],
                            "total_costs": [["currency": "CNY", "amount": "16.09"]],
                        ],
                    ],
                ]
            case "/api/v0/usage/amount":
                body = Self.envelope(bizData: ["days": [[
                    "date": today,
                    "data": [["usage": [
                        ["type": "PROMPT_CACHE_HIT_TOKEN", "amount": "30"],
                        ["type": "PROMPT_CACHE_MISS_TOKEN", "amount": "10"],
                        ["type": "RESPONSE_TOKEN", "amount": "100"],
                    ]]],
                ]]])
            case "/api/v0/usage/cost":
                body = Self.envelope(bizData: costData)
            default:
                XCTFail("Unexpected DeepSeek URL: \(request.url?.absoluteString ?? "nil")")
                body = Self.envelope(bizData: [:])
            }

            let data = try JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: path == "/api/v0/usage/cost" ? costStatus : 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
        defer { MockDeepSeekURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepSeekURLProtocol.self]
        let service = DeepSeekUsageService(session: URLSession(configuration: configuration))

        return try await service.fetchSnapshot()
    }

    private static func envelope(bizData: Any) -> [String: Any] {
        [
            "code": 0,
            "data": [
                "biz_code": 0,
                "biz_data": bizData,
            ],
        ]
    }
}

private final class MockDeepSeekURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
