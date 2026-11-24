import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Page: Hashable {
        case general
        case provider(ProviderID)

        var title: String {
            switch self {
            case .general: "General"
            case .provider(let provider): provider.displayName
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .provider(.antigravity): "sparkles"
            case .provider(.grok): "bolt"
            case .provider: "terminal"
            }
        }
    }

    @ObservedObject var model: AppModel
    @ObservedObject var claudeModel: ClaudeModel
    @ObservedObject var deepSeekModel: DeepSeekModel
    @ObservedObject var antigravityModel: AntigravityModel
    @ObservedObject var grokModel: GrokModel
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(AppSettings.refreshIntervalKey) private var refreshIntervalSeconds = 300.0
    @AppStorage(AppSettings.initialRefreshDelaySecondsKey) private var initialRefreshDelaySeconds = AppSettings.defaultInitialRefreshDelaySeconds
    @AppStorage(AppSettings.showMenuBarNumbersKey) private var showMenuBarNumbers = AppSettings.defaultShowMenuBarNumbers
    @AppStorage(AppSettings.antigravityThirdPartyDisplayKey) private var antigravityThirdPartyDisplay = AppSettings.defaultAntigravityThirdPartyDisplay
    @AppStorage(AppSettings.claudeSessionCookieKey) private var claudeSessionCookie = ""
    @AppStorage(AppSettings.deepSeekBearerTokenKey) private var deepSeekBearerToken = ""
    @AppStorage(AppSettings.deepSeekBalanceThresholdKey) private var deepSeekBalanceThreshold = AppSettings.defaultDeepSeekBalanceThreshold
    @AppStorage(AppSettings.deepSeekWarningPercentKey) private var deepSeekWarningPercent = AppSettings.defaultDeepSeekWarningPercent
    @State private var cookieDraft = ""
    @State private var deepSeekTokenDraft = ""
    @State private var page: Page = .general

    init(model: AppModel, claudeModel: ClaudeModel, deepSeekModel: DeepSeekModel, antigravityModel: AntigravityModel, grokModel: GrokModel) {
        self.model = model
        self.claudeModel = claudeModel
        self.deepSeekModel = deepSeekModel
        self.antigravityModel = antigravityModel
        self.grokModel = grokModel
        self._loginManager = ObservedObject(wrappedValue: model.loginManager)
    }

    var body: some View {
        HStack(spacing: 0) {
            self.sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(self.page.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                self.pageContent
                    .id(self.page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            self.cookieDraft = self.claudeSessionCookie
            self.deepSeekTokenDraft = self.deepSeekBearerToken
            let balanceSettings = AppSettings.deepSeekBalanceSettings()
            self.deepSeekBalanceThreshold = balanceSettings.fullBalance
            self.deepSeekWarningPercent = balanceSettings.warningPercent
            self.loginManager.refreshStatus()
        }
    }

    private var sidebar: some View {
        List(selection: Binding<Page?>(
            get: { self.page },
            set: { if let page = $0 { self.page = page } }
        )) {
            self.sidebarRow(.general)
            Section("Providers") {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    self.sidebarRow(.provider(provider))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 156)
        .accessibilityLabel("Settings sections")
    }

    private func sidebarRow(_ page: Page) -> some View {
        Label {
            Text(page.title)
        } icon: {
            if case .provider(let provider) = page,
               let icon = ProviderSidebarImages.image(for: provider, dark: self.colorScheme == .dark) {
                Image(nsImage: icon)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: page.symbol)
            }
        }
        .tag(page)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch self.page {
        case .general: self.generalTab()
        case .provider(.claude): self.claudeTab()
        case .provider(.codex): self.codexTab()
        case .provider(.antigravity): self.antigravityTab()
        case .provider(.grok): self.grokTab()
        case .provider(.deepSeek): self.deepSeekTab()
        }
    }

    // MARK: - General

    @ViewBuilder
    private func generalTab() -> some View {
        self.settingsScrollView {
            self.settingsSection(title: "Startup", systemImage: "power") {
                self.settingsCard {
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { self.loginManager.isEnabled },
                                set: { self.loginManager.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message = self.loginManager.errorMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            self.settingsSection(title: "Menu Bar", systemImage: "menubar.rectangle") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show numbers in the menu bar", isOn: self.$showMenuBarNumbers)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Turn off for rings only. Numbers stay visible in the drop-down.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            self.settingsSection(title: "Refresh", systemImage: "arrow.clockwise") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Text("Interval")
                            Spacer(minLength: 12)
                            Picker("Interval", selection: self.$refreshIntervalSeconds) {
                                Text("1 minute").tag(60.0)
                                Text("5 minutes").tag(300.0)
                                Text("15 minutes").tag(900.0)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 260, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Initial sync delay")
                                Spacer()
                                Text(Formatting.duration(seconds: Int(self.initialRefreshDelaySeconds.rounded())))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: self.$initialRefreshDelaySeconds,
                                in: 10...120,
                                step: 10
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("10s")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } maximumValueLabel: {
                                Text("2m")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Applies on next app launch.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Claude

    @ViewBuilder
    private func claudeTab() -> some View {
        self.settingsScrollView(provider: .claude) {
            self.trackingSettings("Claude", provider: .claude, enabled: self.$claudeModel.isEnabled)

            self.connectionSettings(
                method: "Session Cookie",
                instructions: "Sign in at **claude.ai**. Open the browser’s developer tools, select **Network**, and reload the page. Copy the **Cookie** request header, then paste and save it below."
            ) {
                self.credentialEditor("Paste session cookie", draft: self.$cookieDraft,
                                      saved: self.$claudeSessionCookie, enabled: self.claudeModel.isEnabled) {
                    self.claudeModel.refreshNow()
                }
            }

            let configured = !self.claudeSessionCookie.isEmpty
            self.providerStatus(enabled: self.claudeModel.isEnabled, refreshing: self.claudeModel.isRefreshing,
                                error: self.claudeModel.errorMessage, canRefresh: configured,
                                message: configured ? "Waiting for first refresh…" : "No session cookie configured.",
                                connected: configured && self.claudeModel.snapshot != nil) {
                self.claudeModel.refreshNow()
            }
        }
    }

    // MARK: - Codex

    @ViewBuilder
    private func codexTab() -> some View {
        self.settingsScrollView(provider: .codex) {
            self.trackingSettings("Codex", provider: .codex, enabled: self.$model.isEnabled)

            self.connectionSettings(
                method: "Codex sign-in",
                instructions: "Sign in to Codex first, then choose **Refresh Now**. AI Usage Bar uses the existing local session; there’s nothing to paste here."
            )
            self.providerStatus(enabled: self.model.isEnabled, refreshing: self.model.isRefreshing,
                                error: self.model.errorMessage,
                                message: self.model.snapshot == nil ? "Waiting for first refresh…" : "Live quota not available.",
                                connected: self.model.snapshot?.rateLimits != nil) {
                self.model.refreshNow()
            }
        }
    }

    // MARK: - DeepSeek

    @ViewBuilder
    private func deepSeekTab() -> some View {
        self.settingsScrollView(provider: .deepSeek) {
            self.trackingSettings("DeepSeek", provider: .deepSeek, enabled: self.$deepSeekModel.isEnabled)

            self.connectionSettings(
                method: "Bearer Token",
                instructions: "Sign in at **platform.deepseek.com**. Open the browser’s developer tools, select **Console**, and run the command below. Paste and save the returned dashboard token, not an API key."
            ) {
                Text(verbatim: "JSON.parse(localStorage.getItem('userToken')).value")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                self.credentialEditor("Paste bearer token", draft: self.$deepSeekTokenDraft,
                                      saved: self.$deepSeekBearerToken, enabled: self.deepSeekModel.isEnabled) {
                    self.deepSeekModel.refreshNow()
                }
            }

            let configured = !self.deepSeekBearerToken.isEmpty
            self.providerStatus(enabled: self.deepSeekModel.isEnabled, refreshing: self.deepSeekModel.isRefreshing,
                                error: self.deepSeekModel.errorMessage, canRefresh: configured,
                                message: configured ? "Waiting for first refresh…" : "No bearer token configured.",
                                connected: configured && self.deepSeekModel.snapshot != nil) {
                self.deepSeekModel.refreshNow()
            }

            self.settingsSection(title: "Balance", systemImage: "dollarsign.circle") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PresetValueSlider(
                            "Full ring balance", value: self.$deepSeekBalanceThreshold,
                            presets: DeepSeekBalanceSettings.balancePresets,
                            format: { String(format: "¥%.0f", $0) }
                        )
                        Divider()
                        PresetValueSlider(
                            "Low balance warning", value: self.$deepSeekWarningPercent,
                            presets: DeepSeekBalanceSettings.warningPresets,
                            format: { String(format: "%.0f%%", $0) }
                        )
                        Text(String(format: "Warn when balance ≤ ¥%.2f.", DeepSeekBalanceSettings(
                            fullBalance: self.deepSeekBalanceThreshold,
                            warningPercent: self.deepSeekWarningPercent
                        ).warningAmount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        }
    }

    private func ringColorSettings(_ provider: ProviderID) -> some View {
        self.settingsSection(title: "Ring Color", systemImage: "paintpalette") {
            self.settingsCard { ProviderRingColorPicker(provider: provider) }
        }
    }

    private func trackingSettings(_ name: String, provider: ProviderID, enabled: Binding<Bool>) -> some View {
        self.settingsSection(title: "Tracking and display", systemImage: "power") {
            self.settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("\(name) usage tracking", isOn: enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    ProviderDisplayPicker(provider: provider,
                                          title: provider == .antigravity ? AntigravityQuotaSnapshot.Pool.gemini.title : "Show usage in")
                        .disabled(!enabled.wrappedValue)
                    if provider == .antigravity {
                        Picker(AntigravityQuotaSnapshot.Pool.thirdParty.title, selection: self.$antigravityThirdPartyDisplay) {
                            Text("Do not show").tag(AntigravityThirdPartyDisplay.hidden)
                            Text("Drop-down only").tag(AntigravityThirdPartyDisplay.menuOnly)
                            Text("Menu bar and drop-down").tag(AntigravityThirdPartyDisplay.menuBarAndMenu)
                        }
                        .disabled(!enabled.wrappedValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func antigravityTab() -> some View {
        self.settingsScrollView(provider: .antigravity) {
            self.trackingSettings(ProviderID.antigravity.displayName, provider: .antigravity, enabled: self.$antigravityModel.isEnabled)
            self.connectionSettings(
                method: "Antigravity CLI",
                instructions: "Sign in to `agy`, choose **Connect Status Line**, then open a new `agy` session. Use `/usage` there to refresh the quota snapshot."
            ) {
                HStack {
                    Button("Connect Status Line") { self.antigravityModel.connect() }
                        .disabled(!self.antigravityModel.isEnabled)
                    Link("Setup Guide", destination: URL(string: "https://antigravity.google/docs/cli/statusline/")!)
                }
            }
            self.providerStatus(enabled: self.antigravityModel.isEnabled, refreshing: false,
                                error: self.antigravityModel.errorMessage,
                                message: self.antigravityModel.isStale ? "Snapshot is stale. Run /usage in agy." : "Waiting for a CLI snapshot…",
                                connected: self.antigravityModel.snapshot != nil && !self.antigravityModel.isStale,
                                refreshTitle: "Read Snapshot") {
                self.antigravityModel.refreshNow()
            }
        }
    }

    private func grokTab() -> some View {
        self.settingsScrollView(provider: .grok) {
            self.trackingSettings("Grok", provider: .grok, enabled: self.$grokModel.isEnabled)
            self.connectionSettings(
                method: "Grok Build CLI",
                instructions: "Install Grok Build, run `grok login` in Terminal, then choose **Refresh Now**. If the CLI isn’t found automatically, choose its executable below."
            ) {
                LabeledContent("Executable", value: self.grokModel.executablePath.isEmpty ? "Automatic" : self.grokModel.executablePath)
                    .lineLimit(2)
                HStack {
                    Button("Choose Executable…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            self.grokModel.setExecutablePath(url.path)
                        }
                    }
                    Button("Use Automatic") { self.grokModel.setExecutablePath("") }
                        .disabled(self.grokModel.executablePath.isEmpty)
                }
                HStack {
                    Link("Setup Guide", destination: URL(string: "https://docs.x.ai/build/overview")!)
                    Link("Open Grok Usage", destination: URL(string: "https://grok.com/dashboard")!)
                }
            }
            self.providerStatus(enabled: self.grokModel.isEnabled, refreshing: self.grokModel.isRefreshing,
                                error: self.grokModel.errorMessage, connected: self.grokModel.snapshot != nil) {
                self.grokModel.refreshNow()
            }
        }
    }

    private func connectionSettings(method: String, instructions: LocalizedStringKey) -> some View {
        self.connectionSettings(method: method, instructions: instructions) { EmptyView() }
    }

    private func connectionSettings<Content: View>(method: String, instructions: LocalizedStringKey,
                                                   @ViewBuilder content: () -> Content) -> some View {
        self.settingsSection(title: "Connection", systemImage: "link") {
            self.settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(method).font(.subheadline.weight(.semibold))
                    Text(instructions).font(.footnote).foregroundStyle(.secondary)
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func credentialEditor(_ placeholder: String, draft: Binding<String>, saved: Binding<String>,
                                  enabled: Bool, didSave: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: draft, axis: .vertical)
                .lineLimit(3...5)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
            HStack {
                Button("Save") {
                    saved.wrappedValue = draft.wrappedValue
                    didSave()
                }
                .disabled(!enabled || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !saved.wrappedValue.isEmpty {
                    Button("Clear", role: .destructive) {
                        draft.wrappedValue = ""
                        saved.wrappedValue = ""
                    }
                }
            }
        }
    }

    private func providerStatus(enabled: Bool, refreshing: Bool, error: String?, canRefresh: Bool = true,
                                message: String = "Waiting for first refresh…", connected: Bool,
                                refreshTitle: String = "Refresh Now", refresh: @escaping () -> Void) -> some View {
        self.settingsSection(title: "Status", systemImage: "info.circle") {
            self.settingsCard {
                HStack(spacing: 12) {
                    if !enabled {
                        Text("Tracking is off").foregroundStyle(.secondary)
                    } else if refreshing {
                        ProgressView("Refreshing…").controlSize(.small)
                    } else if let error, canRefresh {
                        Label(error, systemImage: "xmark.circle.fill").foregroundStyle(.red)
                            .lineLimit(3).help(error)
                    } else if connected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                    } else {
                        Text(message).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(refreshTitle, action: refresh)
                        .fixedSize()
                        .disabled(!enabled || refreshing || !canRefresh)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func settingsScrollView<Content: View>(provider: ProviderID? = nil, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
                if let provider { self.ringColorSettings(provider) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}

private struct ProviderDisplayPicker: View {
    let title: String
    @AppStorage private var placement: ProviderDisplay

    init(provider: ProviderID, title: String) {
        self.title = title
        self._placement = AppStorage(wrappedValue: .menuBarAndMenu, AppSettings.displayKey(for: provider))
    }

    var body: some View {
        Picker(self.title, selection: self.$placement) {
            Text("Drop-down only").tag(ProviderDisplay.menuOnly)
            Text("Menu bar and drop-down").tag(ProviderDisplay.menuBarAndMenu)
        }
    }
}

private struct ProviderRingColorPicker: View {
    let provider: ProviderID
    @AppStorage private var hex: String

    init(provider: ProviderID) {
        self.provider = provider
        self._hex = AppStorage(wrappedValue: "", provider.ringColorKey)
    }

    var body: some View {
        HStack {
            ColorPicker("Menu bar ring", selection: Binding(
                get: { Color(nsColor: self.provider.ringColor(override: self.hex)) },
                set: { color in
                    if let rgb = NSColor(color).usingColorSpace(.sRGB) { self.hex = rgb.toHex() }
                }
            ), supportsOpacity: false)

            Spacer()
            Button("Restore Default") { self.hex = "" }
                .disabled(self.hex.isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
