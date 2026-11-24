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

enum CodexRateLimitWindowKind: Equatable {
    case fiveHour
    case weekly

    init?(durationSeconds: Int) {
        switch durationSeconds {
        case 5 * 60 * 60:
            self = .fiveHour
        case 7 * 24 * 60 * 60:
            self = .weekly
        default:
            return nil
        }
    }
}

struct RateLimitSnapshot: Sendable {
    let fiveHourRemainingPercent: Double?
    let fiveHourResetsAt: Date?
    let weeklyRemainingPercent: Double?
    let weeklyResetsAt: Date?
    let creditsRemaining: String?
    let sourceLabel: String
}
