import AppKit
import SwiftUI

/// Unified usage dropdown, shown from a single menu bar item.
struct CombinedMenuContentView: View {
    @AppStorage(AppSettings.antigravityThirdPartyDisplayKey) private var antigravityThirdPartyDisplay = AppSettings.defaultAntigravityThirdPartyDisplay

    @ObservedObject var claudeModel: ClaudeModel
    @ObservedObject var codexModel: AppModel
    @ObservedObject var deepSeekModel: DeepSeekModel
    @ObservedObject var antigravityModel: AntigravityModel
    @ObservedObject var grokModel: GrokModel
    let openSettings: () -> Void

    var body: some View {
        let providers = self.trackedProviders
        VStack(alignment: .leading, spacing: 14) {
            if !providers.isEmpty {
                self.providerSections(providers)
            } else {
                Text("No providers are tracking usage. Open Settings to enable one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()

            // Action bar
            HStack {
                HoverIconButton(systemName: "arrow.clockwise", help: "Refresh all") {
                    if self.claudeModel.isEnabled { self.claudeModel.refreshNow() }
                    if self.codexModel.isEnabled { self.codexModel.refreshNow() }
                    if self.deepSeekModel.isEnabled { self.deepSeekModel.refreshNow() }
                    if self.antigravityModel.isEnabled { self.antigravityModel.refreshNow() }
                    if self.grokModel.isEnabled { self.grokModel.refreshNow() }
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
    }

    private var trackedProviders: [ProviderID] {
        ProviderID.allCases.filter {
            switch $0 {
            case .claude: self.claudeModel.isEnabled
            case .codex: self.codexModel.isEnabled
            case .antigravity: self.antigravityModel.isEnabled
            case .grok: self.grokModel.isEnabled
            case .deepSeek: self.deepSeekModel.isEnabled
            }
        }
    }

    private func providerSections(_ providers: [ProviderID]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(providers, id: \.self) { provider in
                if provider != providers.first { Divider() }
                switch provider {
                case .claude: self.claudeSection()
                case .codex: self.codexSection()
                case .antigravity: self.antigravitySection()
                case .grok: self.grokSection()
                case .deepSeek: self.deepSeekSection()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerHeader(_ name: String, url: URL, refreshedAt: Date?) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.headline)
            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12, height: 12)
            }
            .help("Open \(name) usage")
            Spacer()
            if let refreshedAt { Self.refreshedText(refreshedAt) }
        }
    }

    private func antigravitySection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.providerHeader(ProviderID.antigravity.displayName, url: URL(string: "https://antigravity.google/docs/plans")!, refreshedAt: self.antigravityModel.snapshot?.capturedAt)
            if let snapshot = self.antigravityModel.snapshot {
                let pools = snapshot.displayedPools(thirdPartyDisplay: self.antigravityThirdPartyDisplay)
                if pools.isEmpty {
                    Text("No Antigravity quota to display.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(pools, id: \.self) { pool in
                    let windows = snapshot.windows.filter { $0.pool == pool }
                    if self.antigravityThirdPartyDisplay.showsPoolTitle(pool) {
                        Text(pool.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(windows, id: \.period) { window in
                        let display = window.display
                        self.usageWindowRow(title: display.title, value: "\(display.percentageText) remaining",
                                            resetsAt: display.resetsAt)
                    }
                }
            } else if let error = self.antigravityModel.errorMessage {
                self.usageError(error)
            } else {
                Text("Connect Status Line in Settings, then open the Antigravity CLI.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func grokSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.providerHeader("Grok", url: URL(string: "https://grok.com/dashboard")!, refreshedAt: self.grokModel.snapshot?.refreshedAt)
            if let snapshot = self.grokModel.snapshot {
                if let window = snapshot.window {
                    self.usageWindowRow(title: window.title, value: "\(window.percentageText) remaining", resetsAt: window.resetsAt)
                } else {
                    Text("Subscription quota not reported.").font(.footnote).foregroundStyle(.secondary)
                }
                if let balance = snapshot.prepaidText {
                    self.usageRow(title: "Extra Usage Credits", value: balance)
                }
            } else if let error = self.grokModel.errorMessage {
                self.usageError(error)
            } else if self.grokModel.isRefreshing {
                ProgressView("Refreshing…").controlSize(.small)
            } else {
                Text("Waiting for first refresh…").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Claude

    @ViewBuilder
    private func claudeSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.providerHeader("Claude", url: URL(string: "https://claude.ai/settings/usage")!,
                                refreshedAt: self.claudeModel.snapshot?.refreshedAt)

            if let snapshot = self.claudeModel.snapshot {
                if let window = snapshot.fiveHour {
                    self.claudeWindowRow(title: "5 hours", window: window)
                }
                if let window = snapshot.sevenDay {
                    self.claudeWindowRow(title: "Weekly", window: window)
                }
                if let window = snapshot.fableWeekly {
                    self.claudeWindowRow(title: "Fable Weekly", window: window)
                }
                if let extra = snapshot.extraUsage, Self.hasDisplayableClaudeExtraUsage(extra) {
                    if extra.usedCredits > 0 {
                        self.usageRow(title: "Extra Usage", value: String(format: "$%.2f used", extra.usedCredits / 100.0))
                    }
                    if let limit = extra.monthlyLimit, limit > 0 {
                        self.usageRow(title: "Monthly Limit", value: String(format: "$%.2f", limit / 100.0))
                    }
                }
                if let balance = snapshot.creditBalance {
                    self.usageRow(title: "Balance", value: Self.claudeMoneyString(balance))
                }
            } else if let dueAt = self.claudeModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.claudeModel.isRefreshing {
                ProgressView("Refreshing…")
                    .controlSize(.small)
            } else if AppSettings.claudeSessionCookie.isEmpty {
                Text("No cookie configured. Open Settings to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.claudeModel.errorMessage {
                self.usageError(error)
            }
        }
    }

    @ViewBuilder
    private func claudeWindowRow(title: String, window: ClaudeRateLimitWindow) -> some View {
        self.usageWindowRow(title: title, value: Self.percentString(window.remainingPercent), resetsAt: window.resetsAt)
    }

    // MARK: - Codex

    @ViewBuilder
    private func codexSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            self.providerHeader("Codex", url: URL(string: "https://chatgpt.com/settings/usage")!,
                                refreshedAt: self.codexModel.snapshot?.refreshedAt)

            if let snapshot = self.codexModel.snapshot {
                if let rateLimits = snapshot.rateLimits {
                    if let remaining = rateLimits.fiveHourRemainingPercent {
                        self.usageWindowRow(title: "5 hours", value: Self.percentString(remaining), resetsAt: rateLimits.fiveHourResetsAt)
                    }
                    if let remaining = rateLimits.weeklyRemainingPercent {
                        self.usageWindowRow(title: "Weekly", value: Self.percentString(remaining), resetsAt: rateLimits.weeklyResetsAt)
                    }
                    if let creditsRemaining = rateLimits.creditsRemaining {
                        self.usageRow(title: "Credits", value: "\(creditsRemaining) remaining")
                    }
                } else if self.codexModel.errorMessage == nil {
                    Text("Live usage source not connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let dueAt = self.codexModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.codexModel.isRefreshing {
                ProgressView("Refreshing…")
                    .controlSize(.small)
            } else if self.codexModel.errorMessage == nil {
                Text("No Codex data loaded yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.codexModel.errorMessage {
                self.usageError(error)
            }
        }
    }

    @ViewBuilder
    private func usageWindowRow(title: String, value: String, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            self.usageRow(title: title, value: value)
            if let resetsAt {
                Self.resetTimeText(resetsAt)
            }
        }
    }

    @ViewBuilder
    private func usageRow(title: String, value: String) -> some View {
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
            self.providerHeader("DeepSeek", url: URL(string: "https://platform.deepseek.com/usage")!,
                                refreshedAt: self.deepSeekModel.snapshot?.refreshedAt)

            if let snapshot = self.deepSeekModel.snapshot {
                self.usageRow(title: "Balance", value: Self.deepSeekAmountText(snapshot.balance))
                self.usageRow(title: "Cache hit rate", value: String(format: "%.2f%%", snapshot.cacheHitRate))
                self.usageRow(title: "Today cost", value: Self.deepSeekAmountText(snapshot.todayCost))
                self.usageRow(title: "Monthly cost", value: Self.deepSeekAmountText(snapshot.monthlyCost))
            } else if let dueAt = self.deepSeekModel.pendingInitialRefreshDueAt {
                Self.initialRefreshText("Initial sync starts in", until: dueAt)
            } else if self.deepSeekModel.isRefreshing {
                ProgressView("Refreshing…")
                    .controlSize(.small)
            } else if AppSettings.deepSeekBearerToken.isEmpty {
                Text("No token configured. Open Settings to add one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = self.deepSeekModel.errorMessage {
                self.usageError(error)
            }
        }
    }

    private func usageError(_ error: String) -> some View {
        Label(error, systemImage: "xmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .lineLimit(3)
            .help(error)
    }

    // MARK: - Helpers

    private static func deepSeekAmountText(_ amount: Double?) -> String {
        amount.map { String(format: "¥%.2f", $0) } ?? "Unavailable"
    }

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

    private static func percentString(_ value: Double?) -> String {
        guard let value else { return "Unknown" }
        return "\(Int(value.rounded()))% remaining"
    }

    private static func hasDisplayableClaudeExtraUsage(_ extra: ClaudeExtraUsage) -> Bool {
        extra.usedCredits > 0 || (extra.monthlyLimit ?? 0) > 0
    }

    private static func claudeMoneyString(_ amount: ClaudeMoneyAmount) -> String {
        let majorAmount = amount.amountMinor / pow(10, Double(amount.exponent))
        let currency = amount.currency.uppercased()
        let prefix = currency == "USD" ? "$" : "\(currency) "
        return String(format: "%@%.*f", prefix, amount.exponent, majorAmount)
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
