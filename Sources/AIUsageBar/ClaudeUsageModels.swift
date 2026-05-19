import Foundation

struct ClaudeUsageSnapshot: Sendable, UsageSnapshotResets {
    let refreshedAt: Date
    let fiveHour: ClaudeRateLimitWindow?
    let sevenDay: ClaudeRateLimitWindow?
    /// Extra usage info from the API (Pro plan add-on credits).
    let extraUsage: ClaudeExtraUsage?

    var resetDates: [Date?] {
        [fiveHour?.resetsAt, sevenDay?.resetsAt]
    }
}

/// Extra usage credits info returned by the usage API.
struct ClaudeExtraUsage: Sendable {
    let isEnabled: Bool
    /// Monthly spending limit in cents, nil if no limit set.
    let monthlyLimit: Double?
    /// Credits used this period in cents.
    let usedCredits: Double
    /// Utilization percentage if available.
    let utilization: Double?
}

struct ClaudeRateLimitWindow: Sendable {
    /// Percentage of the rate limit already used (0–100).
    let utilization: Double
    /// When this window resets.
    let resetsAt: Date?

    /// Remaining percentage (100 − utilization), clamped to 0–100.
    var remainingPercent: Double {
        min(100, max(0, 100 - self.utilization))
    }
}

// MARK: - JSON response types

struct ClaudeUsageResponse: Decodable, Sendable {
    let fiveHour: WindowPayload?
    let sevenDay: WindowPayload?
    let extraUsage: ExtraUsagePayload?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
    }

    struct WindowPayload: Decodable, Sendable {
        let utilization: Double?
        let resetsAt: String?

        private enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct ExtraUsagePayload: Decodable, Sendable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?

        private enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
        }
    }
}

// MARK: - Bootstrap response

struct BootstrapResponse: Decodable {
    struct Account: Decodable {
        let lastActiveOrgId: String?
    }
    let account: Account?

    var orgId: String? {
        guard let id = account?.lastActiveOrgId, !id.isEmpty else { return nil }
        return id
    }
}
