import CoreFoundation
import Darwin
import Foundation

struct AntigravityQuotaSnapshot: Codable, Equatable {
    enum Pool: String, CaseIterable, Codable {
        case gemini
        case thirdParty = "3p"
        case argon = "gemini-argon-wtu"

        var title: String {
            switch self {
            case .gemini: "Gemini Models"
            case .thirdParty: "Claude and GPT Models"
            case .argon: "Gemini Argon"
            }
        }
    }

    enum Period: String, CaseIterable, Codable {
        case fiveHours = "5h"
        case weekly

        var title: String { self == .fiveHours ? "5 hours" : "Weekly" }
    }

    struct Window: Codable, Equatable {
        let pool: Pool
        let period: Period
        let remaining: Double
        let resetsAt: Date?

        var display: SubscriptionWindow {
            SubscriptionWindow(title: self.period.title, remainingFraction: self.remaining, resetsAt: self.resetsAt)
        }
    }

    struct MenuWindows: Equatable {
        var fiveHours: SubscriptionWindow? = nil
        var weekly: SubscriptionWindow? = nil
    }

    static let maxAge: TimeInterval = 30 * 60
    let capturedAt: Date
    let windows: [Window]

    func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(self.capturedAt) >= Self.maxAge ||
            self.windows.contains { $0.resetsAt.map { $0 <= now } ?? false }
    }

    func displayedPools(thirdPartyDisplay: AntigravityThirdPartyDisplay) -> [Pool] {
        Pool.allCases.filter { pool in
            (pool != .thirdParty || thirdPartyDisplay.showsInDropDown) && self.windows.contains { $0.pool == pool }
        }
    }

    func menuWindows(for pool: Pool, at now: Date) -> MenuWindows {
        MenuWindows(fiveHours: self.menuWindow(.fiveHours, for: pool, at: now),
                    weekly: self.menuWindow(.weekly, for: pool, at: now))
    }

    private func menuWindow(_ period: Period, for pool: Pool, at now: Date) -> SubscriptionWindow? {
        guard now.timeIntervalSince(self.capturedAt) < Self.maxAge else { return nil }
        return self.windows.first {
            $0.pool == pool && $0.period == period && ($0.resetsAt.map { $0 > now } ?? true)
        }?.display
    }

    static func capture(_ data: Data, at capturedAt: Date) throws -> Self? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let quota = root?["quota"] as? [String: Any] else { return nil }
        let windows: [Window] = Pool.allCases.flatMap { pool in
            Period.allCases.compactMap { period in
                guard let bucket = quota["\(pool.rawValue)-\(period.rawValue)"] as? [String: Any],
                      bucket["disabled"] as? Bool != true,
                      let fraction = self.number(bucket["remaining_fraction"]), (0...1).contains(fraction)
                else { return nil }

                let absolute = SubscriptionUsage.date(bucket["reset_time"] as? String)
                let seconds = self.number(bucket["reset_in_seconds"])
                let reset: Date? = if let absolute, absolute > capturedAt {
                    absolute
                } else if let seconds, seconds > 0 {
                    capturedAt.addingTimeInterval(seconds)
                } else {
                    nil
                }
                return Window(pool: pool, period: period, remaining: fraction, resetsAt: reset)
            }
        }
        guard !windows.isEmpty else { return nil }
        return Self(capturedAt: capturedAt, windows: windows)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}

struct AntigravityStatusLine {
    static let captureArgument = "--capture-antigravity-statusline"
    static let connectArgument = "--connect-antigravity-statusline"
    private static let maxPayloadBytes = 256 * 1024

    let cliDirectory: URL
    let executable: URL

    init(cliDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gemini/antigravity-cli"),
         executable: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])) {
        self.cliDirectory = cliDirectory
        self.executable = executable
    }

    private var cacheDirectory: URL { self.cliDirectory.appending(path: "ai-usage-bar") }
    var snapshotURL: URL { self.cacheDirectory.appending(path: "quota.json") }
    private var settingsURL: URL { self.cliDirectory.appending(path: "settings.json") }

    var command: String {
        "'\(self.executable.path.replacingOccurrences(of: "'", with: "'\\''"))' \(Self.captureArgument)"
    }

    enum SetupError: LocalizedError {
        case cliMissing, invalidSettings, existingCommand

        var errorDescription: String? {
            switch self {
            case .cliMissing: "Run and sign in to the Antigravity CLI before connecting it."
            case .invalidSettings: "Could not read Antigravity CLI settings. No settings were changed."
            case .existingCommand: "Antigravity already has a custom status line. It was not changed."
            }
        }
    }

    func connect() throws {
        guard FileManager.default.fileExists(atPath: self.cliDirectory.path) else { throw SetupError.cliMissing }
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: self.settingsURL.path) {
            let data = try Data(contentsOf: self.settingsURL)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { throw SetupError.invalidSettings }
            settings = object
        }
        if let existing = settings["statusLine"] {
            guard let statusLine = existing as? [String: Any], statusLine["command"] as? String == self.command
            else { throw SetupError.existingCommand }
            if statusLine["enabled"] as? Bool != false { return }
            var enabled = statusLine
            enabled["enabled"] = true
            settings["statusLine"] = enabled
        } else {
            settings["statusLine"] = ["type": "command", "command": self.command,
                                      "enabled": true, "stack_with_default": true]
        }
        let updated = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try self.writePrivately(updated, to: self.settingsURL)
    }

    func captureFromStdin(isEnabled: () -> Bool) throws {
        guard isEnabled() else { return }
        let data = FileHandle.standardInput.readData(ofLength: Self.maxPayloadBytes + 1)
        try self.capture(data, isEnabled: isEnabled)
    }

    func capture(_ data: Data, isEnabled: () -> Bool) throws {
        guard isEnabled() else { return }
        guard data.count <= Self.maxPayloadBytes,
              let snapshot = try AntigravityQuotaSnapshot.capture(data, at: .now), isEnabled()
        else { return }
        try self.writePrivately(JSONEncoder().encode(snapshot), to: self.snapshotURL)
    }

    func readSnapshot() -> AntigravityQuotaSnapshot? {
        guard let file = try? FileHandle(forReadingFrom: self.snapshotURL),
              let data = try? file.read(upToCount: Self.maxPayloadBytes + 1), data.count <= Self.maxPayloadBytes,
              let snapshot = try? JSONDecoder().decode(AntigravityQuotaSnapshot.self, from: data),
              !snapshot.windows.isEmpty, snapshot.capturedAt <= .now,
              snapshot.windows.allSatisfy({ (0...1).contains($0.remaining) })
        else { return nil }
        return snapshot
    }

    func clearSnapshot() { try? FileManager.default.removeItem(at: self.snapshotURL) }

    private func writePrivately(_ data: Data, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let temp = self.cacheDirectory.appending(path: UUID().uuidString)
        defer { try? manager.removeItem(at: temp) }
        guard manager.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        if rename(temp.path, destination.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
