import Foundation

struct UsageSnapshot: Sendable, UsageSnapshotResets {
    let refreshedAt: Date
    let identity: CodexIdentity?
    let rateLimits: RateLimitSnapshot?

    var resetDates: [Date?] {
        [rateLimits?.fiveHourResetsAt, rateLimits?.weeklyResetsAt]
    }
}

struct CodexIdentity: Sendable {
    let email: String?
    let accountID: String?
    let authMode: String?
}

struct RateLimitSnapshot: Sendable {
    let fiveHourRemainingPercent: Double?
    let fiveHourResetsAt: Date?
    let weeklyRemainingPercent: Double?
    let weeklyResetsAt: Date?
    let creditsRemaining: String?
    let sourceLabel: String
}
