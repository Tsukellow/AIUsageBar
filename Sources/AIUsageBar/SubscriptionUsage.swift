import Foundation

struct SubscriptionWindow: Equatable, Sendable {
    let title: String
    let remainingFraction: Double
    let resetsAt: Date?

    var percentageText: String { "\(Int((self.remainingFraction * 100 + 1e-10).rounded()))%" }
}

enum SubscriptionUsage {
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func remainingFraction(used: Double, scale: Double) -> Double? {
        guard used.isFinite, used >= 0, used <= scale else { return nil }
        return 1 - used / scale
    }
}
