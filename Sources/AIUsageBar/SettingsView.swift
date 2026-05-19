import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var claudeModel: ClaudeModel
    @ObservedObject var deepSeekModel: DeepSeekModel
    @ObservedObject private var loginManager: LaunchAtLoginManager

    @AppStorage(AppSettings.refreshIntervalKey) private var refreshIntervalSeconds = 300.0
    @AppStorage(AppSettings.initialRefreshDelaySecondsKey) private var initialRefreshDelaySeconds = AppSettings.defaultInitialRefreshDelaySeconds
    @AppStorage(AppSettings.claudeSessionCookieKey) private var claudeSessionCookie = ""
    @AppStorage(AppSettings.deepSeekBearerTokenKey) private var deepSeekBearerToken = ""
    @AppStorage(AppSettings.deepSeekBalanceThresholdKey) private var deepSeekBalanceThreshold = AppSettings.defaultDeepSeekBalanceThreshold
    @State private var cookieDraft = ""
    @State private var deepSeekTokenDraft = ""

    init(model: AppModel, claudeModel: ClaudeModel, deepSeekModel: DeepSeekModel) {
        self.model = model
        self.claudeModel = claudeModel
        self.deepSeekModel = deepSeekModel
        self._loginManager = ObservedObject(wrappedValue: model.loginManager)
    }

    var body: some View {
        TabView {
            self.generalTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            self.claudeTab()
                .tabItem {
                    Label("Claude", systemImage: "terminal")
                }

            self.codexTab()
                .tabItem {
                    Label("Codex", systemImage: "terminal")
                }

            self.deepSeekTab()
                .tabItem {
                    Label("DeepSeek", systemImage: "terminal")
                }
        }
        .padding(20)
        .onAppear {
            self.cookieDraft = self.claudeSessionCookie
            self.deepSeekTokenDraft = self.deepSeekBearerToken
            self.loginManager.refreshStatus()
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
        self.settingsScrollView {
            self.settingsSection(title: "Enabled", systemImage: "power") {
                self.settingsCard {
                    HStack {
                        Text("Claude usage tracking")
                        Spacer()
                        Toggle("", isOn: self.$claudeModel.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            self.settingsSection(title: "Session Cookie", systemImage: "key") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Paste cookie here...", text: self.$cookieDraft, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        HStack {
                            Button("Save") {
                                AppSettings.claudeSessionCookie = self.cookieDraft
                                self.claudeSessionCookie = self.cookieDraft
                                self.claudeModel.refreshNow()
                            }
                            .disabled(self.cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.claudeModel.isEnabled)

                            if !self.claudeSessionCookie.isEmpty {
                                Button("Clear", role: .destructive) {
                                    self.cookieDraft = ""
                                    AppSettings.claudeSessionCookie = ""
                                    self.claudeSessionCookie = ""
                                }
                            }

                            Spacer()

                            Button("Refresh Now") {
                                self.claudeModel.refreshNow()
                            }
                            .disabled(self.claudeSessionCookie.isEmpty || !self.claudeModel.isEnabled)
                        }
                    }
                }

                Text("Open **claude.ai** → DevTools (F12) → Network → reload → copy the **Cookie** request header.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            self.settingsSection(title: "Status", systemImage: "info.circle") {
                self.settingsCard {
                    self.claudeStatusContent()
                }
            }
        }
    }

    @ViewBuilder
    private func claudeStatusContent() -> some View {
        if self.claudeModel.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Connecting...").foregroundStyle(.secondary)
            }
        } else if let error = self.claudeModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(error).foregroundStyle(.red)
            }
        } else if self.claudeModel.snapshot != nil {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Connected")
            }
        } else if !AppSettings.claudeSessionCookie.isEmpty {
            Text("Waiting for first refresh...").foregroundStyle(.secondary)
        } else {
            Text("No cookie configured.").foregroundStyle(.secondary)
        }
    }

    // MARK: - Codex

    @ViewBuilder
    private func codexTab() -> some View {
        self.settingsScrollView {
            self.settingsSection(title: "Enabled", systemImage: "power") {
                self.settingsCard {
                    HStack {
                        Text("Codex usage tracking")
                        Spacer()
                        Toggle("", isOn: self.$model.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            self.settingsSection(title: "Actions", systemImage: "arrow.clockwise") {
                self.settingsCard {
                    HStack {
                        Spacer()
                        Button("Refresh Now") {
                            self.model.refreshNow()
                        }
                        .disabled(!self.model.isEnabled)
                    }
                }
            }

            self.settingsSection(title: "Status", systemImage: "info.circle") {
                self.settingsCard {
                    self.codexStatusContent()
                }
            }
        }
    }

    @ViewBuilder
    private func codexStatusContent() -> some View {
        if self.model.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Loading...").foregroundStyle(.secondary)
            }
        } else if let error = self.model.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(error).foregroundStyle(.red)
            }
        } else if self.model.snapshot != nil {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Connected")
            }
        } else {
            Text("No Codex data loaded yet.").foregroundStyle(.secondary)
        }
    }

    // MARK: - DeepSeek

    @ViewBuilder
    private func deepSeekTab() -> some View {
        self.settingsScrollView {
            self.settingsSection(title: "Enabled", systemImage: "power") {
                self.settingsCard {
                    HStack {
                        Text("DeepSeek usage tracking")
                        Spacer()
                        Toggle("", isOn: self.$deepSeekModel.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            self.settingsSection(title: "Bearer Token", systemImage: "key") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Paste token here...", text: self.$deepSeekTokenDraft, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        HStack {
                            Button("Save") {
                                AppSettings.deepSeekBearerToken = self.deepSeekTokenDraft
                                self.deepSeekBearerToken = self.deepSeekTokenDraft
                                self.deepSeekModel.refreshNow()
                            }
                            .disabled(self.deepSeekTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !self.deepSeekModel.isEnabled)

                            if !self.deepSeekBearerToken.isEmpty {
                                Button("Clear", role: .destructive) {
                                    self.deepSeekTokenDraft = ""
                                    AppSettings.deepSeekBearerToken = ""
                                    self.deepSeekBearerToken = ""
                                }
                            }

                            Spacer()

                            Button("Refresh Now") {
                                self.deepSeekModel.refreshNow()
                            }
                            .disabled(self.deepSeekBearerToken.isEmpty || !self.deepSeekModel.isEnabled)
                        }
                    }
                }

                Text("Open **platform.deepseek.com** → F12 → Console → enter:\n`JSON.parse(localStorage.getItem('userToken')).value`")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            self.settingsSection(title: "Balance Threshold", systemImage: "dollarsign.circle") {
                self.settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Threshold")
                            Spacer()
                            Text(String(format: "¥%.0f", self.deepSeekBalanceThreshold))
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: self.$deepSeekBalanceThreshold,
                            in: 10...200,
                            step: 10
                        ) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("¥10").font(.caption).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("¥200").font(.caption).foregroundStyle(.secondary)
                        }

                        Text("Ring shows full when balance reaches this value.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            self.settingsSection(title: "Status", systemImage: "info.circle") {
                self.settingsCard {
                    self.deepSeekStatusContent()
                }
            }
        }
    }

    @ViewBuilder
    private func deepSeekStatusContent() -> some View {
        if self.deepSeekModel.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Connecting...").foregroundStyle(.secondary)
            }
        } else if let error = self.deepSeekModel.errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(error).foregroundStyle(.red)
            }
        } else if self.deepSeekModel.snapshot != nil {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Connected")
            }
        } else if AppSettings.deepSeekBearerToken.isEmpty {
            Text("No token configured.").foregroundStyle(.secondary)
        } else {
            Text("Waiting for first refresh...").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func settingsScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
