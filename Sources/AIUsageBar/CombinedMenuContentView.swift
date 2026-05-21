import AppKit
import SwiftUI

/// Unified dropdown for both Claude and Codex usage, shown from a single menu bar item.
struct CombinedMenuContentView: View {
    @ObservedObject var claudeModel: ClaudeModel
    @ObservedObject var codexModel: AppModel
    @ObservedObject var deepSeekModel: DeepSeekModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if self.claudeModel.isEnabled {
                self.claudeSection()
                Divider()
            }

            if self.codexModel.isEnabled {
                self.codexSection()
                Divider()
            }

            if self.deepSeekModel.isEnabled {
                self.deepSeekSection()
                Divider()
            }

            // Action bar
            HStack {
                HoverIconButton(systemName: "arrow.clockwise", help: "Refresh all") {
                    if self.claudeModel.isEnabled { self.claudeModel.refreshNow() }
                    if self.codexModel.isEnabled { self.codexModel.refreshNow() }
                    if self.deepSeekModel.isEnabled { self.deepSeekModel.refreshNow() }
                }
                .keyboardShortcut("r")

                HoverIconButton(systemName: "gearshape", help: "Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    self.openSettings()
                }

                Spacer()

                HoverIconButton(systemName: "power", help: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Claude

    @ViewBuilder
    private func claudeSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text("Claude")
                    .font(.headline)
                Link(destination: URL(string: "https://claude.ai/settings/usage")!) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 12, height: 12)
                }
                .help("Open Claude usage page")
                Spacer()
                if let snapshot = self.claudeModel.snapshot {
                    Self.refreshedText(snapshot.refreshedAt)
                }
            }

            if let snapshot = self.claudeModel.snapshot {
                if let window = snapshot.fiveHour {
                    self.claudeWindowRow(title: "5 hours", window: window)
                }
                if let window = snapshot.sevenDay {
                    self.claudeWindowRow(title: "Weekly", window: window)
                }
                if let extra = snapshot.extraUsage, Self.hasDisplayableClaudeExtraUsage(extra) {
                    if extra.usedCredits > 0 {
                        HStack {
                            Text("Extra Usage")
                                .foregroundStyle(.secondary)
                            Spacer()
                            // used_credits is in cents
                            Text(String(format: "$%.2f used", extra.usedCredits / 100.0))
                                .font(.body.monospacedDigit())
                        }
                    }
                    if let limit = extra.monthlyLimit, limit > 0 {
                        HStack {
                            Text("Monthly Limit")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", limit / 100.0))
                                .font(.body.monospacedDigit())
                        }
                    }
                }
            } else if let dueAt = self.claudeModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.claudeModel.isRefreshing {
                ProgressView("Loading...")
                    .controlSize(.small)
            } else if AppSettings.claudeSessionCookie.isEmpty {
                Text("No cookie configured. Open Settings to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.claudeModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func claudeWindowRow(title: String, window: ClaudeRateLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% remaining")
                    .font(.body.monospacedDigit())
            }
            if let resetsAt = window.resetsAt {
                Self.resetTimeText(resetsAt)
            }
        }
    }

    // MARK: - Codex

    @ViewBuilder
    private func codexSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text("Codex")
                    .font(.headline)
                Link(destination: URL(string: "https://chatgpt.com/codex/settings/usage")!) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 12, height: 12)
                }
                .help("Open Codex usage page")
                Spacer()
                if let snapshot = self.codexModel.snapshot {
                    Self.refreshedText(snapshot.refreshedAt)
                }
            }

            if let snapshot = self.codexModel.snapshot {
                if let rateLimits = snapshot.rateLimits {
                    self.codexWindowRow(title: "5 hours", value: Self.percentString(rateLimits.fiveHourRemainingPercent), resetsAt: rateLimits.fiveHourResetsAt)
                    self.codexWindowRow(title: "Weekly", value: Self.percentString(rateLimits.weeklyRemainingPercent), resetsAt: rateLimits.weeklyResetsAt)
                    if let creditsRemaining = rateLimits.creditsRemaining {
                        self.codexRow(title: "Credits", value: "\(creditsRemaining) remaining")
                    }
                } else if self.codexModel.errorMessage == nil {
                    Text("Live usage source not connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let dueAt = self.codexModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.codexModel.isRefreshing {
                ProgressView("Loading...")
                    .controlSize(.small)
            } else if self.codexModel.errorMessage == nil {
                Text("No Codex data loaded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.codexModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func codexWindowRow(title: String, value: String, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.body.monospacedDigit())
            }
            if let resetsAt {
                Self.resetTimeText(resetsAt)
            }
        }
    }

    @ViewBuilder
    private func codexRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    // MARK: - DeepSeek

    @ViewBuilder
    private func deepSeekSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text("DeepSeek")
                    .font(.headline)
                Link(destination: URL(string: "https://platform.deepseek.com/usage")!) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 12, height: 12)
                }
                .help("Open DeepSeek usage page")
                Spacer()
                if let snapshot = self.deepSeekModel.snapshot {
                    Self.refreshedText(snapshot.refreshedAt)
                }
            }

            if let snapshot = self.deepSeekModel.snapshot {
                self.deepSeekRow(title: "Balance",
                                 value: String(format: "¥%.2f", snapshot.balance))
                self.deepSeekRow(title: "Cache hit rate",
                                 value: String(format: "%.2f%%", snapshot.cacheHitRate))
                VStack(alignment: .leading, spacing: 4) {
                    self.deepSeekRow(title: "Today tokens",
                                     value: Self.commaNum(snapshot.todayTotalTokens))
                    HStack {
                        Text("Input").foregroundStyle(.tertiary).font(.caption)
                        Spacer()
                        Text(Self.commaNum(snapshot.todayPromptTokens)).font(.caption.monospacedDigit())
                    }
                    HStack {
                        Text("Output").foregroundStyle(.tertiary).font(.caption)
                        Spacer()
                        Text(Self.commaNum(snapshot.todayCompletionTokens)).font(.caption.monospacedDigit())
                    }
                }
                self.deepSeekRow(title: "Today cost",
                                 value: String(format: "¥%.2f", snapshot.todayCost))
                self.deepSeekRow(title: "Monthly cost",
                                 value: String(format: "¥%.2f", snapshot.monthlyCost))
            } else if let dueAt = self.deepSeekModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.deepSeekModel.isRefreshing {
                ProgressView("Loading...")
                    .controlSize(.small)
            } else if AppSettings.deepSeekBearerToken.isEmpty {
                Text("No token configured. Open Settings to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.deepSeekModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func deepSeekRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    // MARK: - Helpers

    private static let absoluteTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE M/d/yy h:mm a")
        return f
    }()

    @ViewBuilder
    private static func resetTimeText(_ date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 4) {
                Text("Resets in \(Formatting.countdown(until: date, relativeTo: context.date))")
                Text("(\(absoluteTimeFormatter.string(from: date)))")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private static func refreshedText(_ date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(Formatting.elapsed(since: date, relativeTo: context.date)) ago")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private static func initialRefreshText(_ prefix: String, until date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("\(prefix) \(Formatting.countdown(until: date, relativeTo: context.date)).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static func commaNum(_ value: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func percentString(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return "\(Int(value.rounded()))% remaining"
    }

    private static func hasDisplayableClaudeExtraUsage(_ extra: ClaudeExtraUsage) -> Bool {
        extra.usedCredits > 0 || (extra.monthlyLimit ?? 0) > 0
    }
}

// MARK: - Hover icon button

private struct HoverIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemName)
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(self.isHovered ? Color.primary.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
        .help(self.help)
    }
}
