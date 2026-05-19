import Foundation

enum Formatting {
    static func duration(seconds totalSeconds: Int) -> String {
        self.durationString(seconds: max(0, totalSeconds))
    }

    static func countdown(until date: Date, relativeTo now: Date) -> String {
        self.durationString(seconds: max(0, Int(date.timeIntervalSince(now).rounded(.down))))
    }

    static func elapsed(since date: Date, relativeTo now: Date) -> String {
        self.durationString(seconds: max(0, Int(now.timeIntervalSince(date).rounded(.down))))
    }

    private static func durationString(seconds totalSeconds: Int) -> String {
        guard totalSeconds > 0 else {
            return "0 sec"
        }

        let daySeconds = 86_400
        let hourSeconds = 3_600
        let minuteSeconds = 60

        let days = totalSeconds / daySeconds
        let hours = (totalSeconds % daySeconds) / hourSeconds
        let minutes = (totalSeconds % hourSeconds) / minuteSeconds
        let seconds = totalSeconds % minuteSeconds

        let components = [
            (days, "day"),
            (hours, "hr"),
            (minutes, "min"),
            (seconds, "sec"),
        ]

        let parts = components
            .filter { $0.0 > 0 }
            .prefix(2)
            .map { "\($0.0) \($0.1)" }

        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }
}
