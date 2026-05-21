import AppKit
import Foundation

// MARK: - NSColor hex helpers

extension NSColor {
    convenience init?(hex: String?) {
        guard let hex else { return nil }
        let stripped = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard stripped.count == 6,
              let value = UInt64(stripped, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    func toHex() -> String {
        let r = Int(round(self.redComponent * 255))
        let g = Int(round(self.greenComponent * 255))
        let b = Int(round(self.blueComponent * 255))
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

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
