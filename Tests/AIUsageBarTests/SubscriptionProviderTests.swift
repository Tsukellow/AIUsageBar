import Foundation
import XCTest
@testable import AIUsageBar

final class SubscriptionProviderTests: XCTestCase {
    func testGrokSubscriptionAndWalletHaveIndependentUnits() throws {
        let snapshot = try GrokUsageSnapshot.decode(Data(#"""
        {"config":{"creditUsagePercent":25,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-30T12:00:00Z"},
        "prepaidBalance":{"val":1234}},"subscription_tier":"SuperGrok"}
        """#.utf8))
        XCTAssertEqual(snapshot.plan, "SuperGrok")
        XCTAssertEqual(snapshot.window?.percentageText, "75%")
        XCTAssertEqual(snapshot.window?.title, "Weekly")
        XCTAssertEqual(snapshot.window?.resetsAt, ISO8601DateFormatter().date(from: "2026-11-30T12:00:00Z"))
        XCTAssertEqual(snapshot.prepaidCents, 1234)
        XCTAssertEqual(snapshot.prepaidText, "$12.34")
    }

    func testGrokMissingUsageIsNotInferredFromTheWallet() throws {
        let snapshot = try GrokUsageSnapshot.decode(Data(#"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY"},"prepaidBalance":{}}}"#.utf8))
        XCTAssertNil(snapshot.window)
        XCTAssertEqual(snapshot.prepaidCents, 0)
        XCTAssertThrowsError(try GrokUsageSnapshot.decode(Data(#"{"config":{"onDemandUsed":{"val":1},"onDemandCap":{"val":50}}}"#.utf8)))

        let exhausted = try GrokUsageSnapshot.decode(Data(#"{"config":{"creditUsagePercent":100,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY"}}}"#.utf8))
        XCTAssertEqual(exhausted.window?.title, "Monthly")
        XCTAssertEqual(exhausted.window?.percentageText, "0%")
        XCTAssertNil(exhausted.prepaidCents)
    }

    @MainActor
    func testGrokCommandOnlySendsInitializeAndBilling() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appending(path: "grok")
        try #"""
        #!/bin/sh
        [ "$1" = agent ] && [ "$2" = stdio ] || exit 1
        IFS= read -r line || exit 2
        case "$line" in *'"method":"initialize"'*) ;; *) exit 3;; esac
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
        IFS= read -r line || exit 4
        case "$line" in *'"method":"_x.ai/billing"'*) ;; *) exit 5;; esac
        printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":42.5,"prepaidBalance":{"val":750}}}}'
        """#.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let snapshot = try await GrokBillingCommand(executable: executable, timeout: .seconds(4)).run()
        XCTAssertEqual(snapshot.window?.percentageText, "58%")
        XCTAssertEqual(snapshot.prepaidCents, 750)
    }

}
