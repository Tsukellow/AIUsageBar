import Foundation
import XCTest
@testable import AIUsageBar

final class AntigravityStatusLineTests: XCTestCase {
    func testObservedWindowsKeepPoolsAndHandleUnsetResetTimes() throws {
        let now = try XCTUnwrap(SubscriptionUsage.date("2026-11-24T05:06:00Z"))
        let data = Data(#"""
        {"email":"ignored@example.test","conversation_title":"private","quota":{
          "gemini-5h":{"remaining_fraction":0.9899333,"reset_time":"2026-11-24T09:03:29Z"},
          "gemini-weekly":{"remaining_fraction":0.9899833,"reset_time":"2026-12-01T04:03:29Z"},
          "3p-5h":{"remaining_fraction":1,"reset_time":"1970-01-01T00:00:00Z","reset_in_seconds":0},
          "3p-weekly":{"remaining_fraction":1,"reset_in_seconds":0}
        }}
        """#.utf8)
        let snapshot = try XCTUnwrap(AntigravityQuotaSnapshot.capture(data, at: now))
        XCTAssertEqual(snapshot.windows.map(\.pool), [.gemini, .gemini, .thirdParty, .thirdParty])
        XCTAssertEqual(snapshot.windows.map(\.period), [.fiveHours, .weekly, .fiveHours, .weekly])
        XCTAssertEqual(snapshot.windows.map { $0.display.percentageText }, ["99%", "99%", "100%", "100%"])
        XCTAssertEqual(snapshot.windows.map(\.resetsAt), [
            SubscriptionUsage.date("2026-11-24T09:03:29Z"),
            SubscriptionUsage.date("2026-12-01T04:03:29Z"), nil, nil
        ])
        let gemini = snapshot.menuWindows(for: .gemini, at: now)
        XCTAssertEqual(gemini.fiveHours?.remainingFraction, 0.9899333)
        XCTAssertEqual(gemini.weekly?.remainingFraction, 0.9899833)
        let thirdParty = snapshot.menuWindows(for: .thirdParty, at: now)
        XCTAssertEqual(thirdParty.fiveHours?.remainingFraction, 1)
        XCTAssertEqual(thirdParty.weekly?.remainingFraction, 1)
        XCTAssertEqual(snapshot.menuWindows(for: .thirdParty, at: now.addingTimeInterval(AntigravityQuotaSnapshot.maxAge)), .init())
        let persisted = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(persisted.contains("example.test"))
        XCTAssertFalse(persisted.contains("private"))
    }

    func testPartialPayloadAndExpiredSnapshotDoNotInventQuota() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(#"""
        {"quota":{"gemini-5h":{"remaining_fraction":0,"reset_in_seconds":60},
        "gemini-weekly":{"remaining_fraction":true},"3p-5h":{"remaining_fraction":1,"disabled":true},
        "3p-weekly":{"remaining_amount":12},"unknown-5h":{"remaining_fraction":1}}}
        """#.utf8)
        let snapshot = try XCTUnwrap(AntigravityQuotaSnapshot.capture(data, at: now))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.menuWindows(for: .gemini, at: now).fiveHours?.percentageText, "0%")
        XCTAssertNil(snapshot.menuWindows(for: .gemini, at: now).weekly)
        XCTAssertEqual(snapshot.menuWindows(for: .thirdParty, at: now), .init())
        XCTAssertFalse(snapshot.isStale(at: now))
        let reset = now.addingTimeInterval(60)
        XCTAssertTrue(snapshot.isStale(at: reset))
        XCTAssertNil(snapshot.menuWindows(for: .gemini, at: reset).fiveHours)
        XCTAssertNil(try AntigravityQuotaSnapshot.capture(Data(#"{"quota":{}}"#.utf8), at: now))
        let noReset = try XCTUnwrap(AntigravityQuotaSnapshot.capture(
            Data(#"{"quota":{"gemini-weekly":{"remaining_fraction":1}}}"#.utf8), at: now))
        let timeout = now.addingTimeInterval(AntigravityQuotaSnapshot.maxAge)
        XCTAssertTrue(noReset.isStale(at: timeout))
        XCTAssertNil(noReset.menuWindows(for: .gemini, at: timeout).weekly)
    }

    func testConnectionIsIdempotentAndPreservesBuiltInAndUserSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = URL(fileURLWithPath: "/Applications/It's an App.app/Contents/MacOS/AIUsageBar")
        let line = AntigravityStatusLine(cliDirectory: directory, executable: executable)
        let settings = directory.appending(path: "settings.json")
        try Data(#"{"other":{"setting":true}}"#.utf8).write(to: settings)
        try line.connect()
        let first = try Data(contentsOf: settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(json["other"] as? [String: Bool], ["setting": true])
        let statusLine = try XCTUnwrap(json["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, line.command)
        XCTAssertTrue(line.command.contains("It'\\''s an App.app"))
        XCTAssertEqual(statusLine["stack_with_default"] as? Bool, true)
        XCTAssertEqual(statusLine["enabled"] as? Bool, true)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions]) as? Int, 0o600)
        try line.connect()
        XCTAssertEqual(try Data(contentsOf: settings), first)

        let existing = Data(#"{"statusLine":{"type":"command","command":"custom"}}"#.utf8)
        try existing.write(to: settings)
        XCTAssertThrowsError(try line.connect())
        XCTAssertEqual(try Data(contentsOf: settings), existing)
    }

    func testCaptureAfterConnectCanReplaceSnapshotOnlyWhileEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let line = AntigravityStatusLine(cliDirectory: directory)
        try line.connect()
        let first = Data(#"{"quota":{"gemini-weekly":{"remaining_fraction":0.75}}}"#.utf8)
        let second = Data(#"{"quota":{"gemini-weekly":{"remaining_fraction":0.50}}}"#.utf8)
        try line.capture(first, isEnabled: { false })
        XCTAssertNil(line.readSnapshot())
        try line.capture(first, isEnabled: { true })
        XCTAssertEqual(line.readSnapshot()?.windows.first?.remaining, 0.75)
        try line.capture(second, isEnabled: { true })
        XCTAssertEqual(line.readSnapshot()?.windows.first?.remaining, 0.50)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: line.snapshotURL.path)[.posixPermissions]) as? Int, 0o600)
        line.clearSnapshot()
        XCTAssertNil(line.readSnapshot())
    }
}
