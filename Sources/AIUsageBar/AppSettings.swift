import Foundation

enum ProviderID: String, CaseIterable {
    // Shared presentation order for Settings, the menu bar and its drop-down.
    case claude, codex, antigravity, grok, deepSeek

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .grok: "Grok"
        case .deepSeek: "DeepSeek"
        }
    }

    // Keep presentation preferences for the former Gemini slot on upgrade.
    var appearanceID: String { self == .antigravity ? "gemini" : self.rawValue }
    var ringColorKey: String { "\(self.appearanceID)RingColorHex" }

    var defaultRingColorHex: String {
        switch self {
        case .claude: "#D97357"
        case .codex: "#FFFFFF"
        case .antigravity: "#96CCFF"
        case .grok: "#9298A3"
        case .deepSeek: "#468CFA"
        }
    }
}

enum ProviderDisplay: String {
    case menuOnly, menuBarAndMenu

    static func menuBarProviders(enabled: Set<ProviderID>, in defaults: UserDefaults = .standard) -> [ProviderID] {
        ProviderID.allCases.filter { enabled.contains($0) && AppSettings.display(for: $0, in: defaults) == .menuBarAndMenu }
    }
}

enum AntigravityThirdPartyDisplay: String {
    case hidden, menuOnly, menuBarAndMenu

    var showsInDropDown: Bool { self != .hidden }

    func showsPoolTitle(_ pool: AntigravityQuotaSnapshot.Pool) -> Bool {
        self != .hidden || pool != .gemini
    }
}

enum MenuBarMeter: Equatable {
    case provider(ProviderID)
    case antigravityThirdParty

    static func visibleMeters(enabled: Set<ProviderID>, hasAntigravityThirdPartyQuota: Bool,
                              in defaults: UserDefaults = .standard) -> [Self] {
        let providers = Set(ProviderDisplay.menuBarProviders(enabled: enabled, in: defaults))
        return ProviderID.allCases.flatMap { provider -> [Self] in
            var meters: [Self] = providers.contains(provider) ? [.provider(provider)] : []
            if provider == .antigravity, enabled.contains(.antigravity), hasAntigravityThirdPartyQuota,
               AppSettings.antigravityThirdPartyDisplay(in: defaults) == .menuBarAndMenu {
                meters.append(.antigravityThirdParty)
            }
            return meters
        }
    }
}

enum MenuBarRingStyle: String {
    case single, dual
}

enum AppSettings {
    static let refreshIntervalKey = "refreshIntervalSeconds"
    static let refreshIntervalMinutes = [1, 3, 5, 10, 15]
    static let defaultRefreshIntervalSeconds = 300.0
    static let initialRefreshDelaySecondsKey = "initialRefreshDelaySeconds"
    static let defaultInitialRefreshDelaySeconds = 60.0
    static let showMenuBarNumbersKey = "showMenuBarNumbers"
    static let defaultShowMenuBarNumbers = true
    static let menuBarRingStyleKey = "menuBarRingStyle"
    static let defaultMenuBarRingStyle: MenuBarRingStyle = .single
    static let antigravityThirdPartyDisplayKey = "antigravityThirdPartyDisplay"
    static let defaultAntigravityThirdPartyDisplay: AntigravityThirdPartyDisplay = .menuOnly

    static func antigravityThirdPartyDisplay(in defaults: UserDefaults = .standard) -> AntigravityThirdPartyDisplay {
        defaults.string(forKey: self.antigravityThirdPartyDisplayKey)
            .flatMap(AntigravityThirdPartyDisplay.init(rawValue:)) ?? self.defaultAntigravityThirdPartyDisplay
    }

    static func showMenuBarNumbers(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: self.showMenuBarNumbersKey) as? Bool ?? self.defaultShowMenuBarNumbers
    }

    static func menuBarRingStyle(in defaults: UserDefaults = .standard) -> MenuBarRingStyle {
        defaults.string(forKey: self.menuBarRingStyleKey)
            .flatMap(MenuBarRingStyle.init(rawValue:)) ?? self.defaultMenuBarRingStyle
    }

    static var refreshIntervalSeconds: Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: self.refreshIntervalKey) == nil {
            defaults.set(self.defaultRefreshIntervalSeconds, forKey: self.refreshIntervalKey)
        }
        return defaults.double(forKey: self.refreshIntervalKey)
    }

    static var initialRefreshDelaySeconds: Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: self.initialRefreshDelaySecondsKey) == nil {
            defaults.set(self.defaultInitialRefreshDelaySeconds, forKey: self.initialRefreshDelaySecondsKey)
        }
        return defaults.double(forKey: self.initialRefreshDelaySecondsKey)
    }

    // MARK: - Model enabled

    static let claudeEnabledKey = "claudeEnabled"
    static let codexEnabledKey = "codexEnabled"
    static let antigravityEnabledKey = "antigravityEnabled"
    static let grokEnabledKey = "grokEnabled"
    static let grokExecutableKey = "grokExecutablePath"

    static func displayKey(for provider: ProviderID) -> String { "providerDisplay.\(provider.appearanceID)" }

    static func display(for provider: ProviderID, in defaults: UserDefaults = .standard) -> ProviderDisplay {
        defaults.string(forKey: self.displayKey(for: provider)).flatMap(ProviderDisplay.init(rawValue:)) ?? .menuBarAndMenu
    }

    static var claudeEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: self.claudeEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: self.claudeEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: self.claudeEnabledKey) }
    }

    static var codexEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: self.codexEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: self.codexEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: self.codexEnabledKey) }
    }

    // MARK: - DeepSeek

    static let deepSeekEnabledKey = "deepSeekEnabled"
    static let deepSeekBearerTokenKey = "deepSeekBearerToken"
    static let deepSeekBalanceThresholdKey = "deepSeekBalanceThreshold"
    static let deepSeekWarningPercentKey = "deepSeekWarningPercent"
    static let defaultDeepSeekBalanceThreshold = DeepSeekBalanceSettings.defaultFullBalance
    static let defaultDeepSeekWarningPercent = DeepSeekBalanceSettings.defaultWarningPercent

    static var deepSeekEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: self.deepSeekEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: self.deepSeekEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: self.deepSeekEnabledKey) }
    }

    static var deepSeekBearerToken: String {
        get { UserDefaults.standard.string(forKey: self.deepSeekBearerTokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: self.deepSeekBearerTokenKey) }
    }

    static var deepSeekBalanceThreshold: Double {
        get { self.deepSeekBalanceSettings().fullBalance }
        set { UserDefaults.standard.set(newValue, forKey: self.deepSeekBalanceThresholdKey) }
    }

    static var deepSeekWarningPercent: Double {
        get { self.deepSeekBalanceSettings().warningPercent }
        set { UserDefaults.standard.set(newValue, forKey: self.deepSeekWarningPercentKey) }
    }

    static func deepSeekBalanceSettings(in defaults: UserDefaults = .standard) -> DeepSeekBalanceSettings {
        DeepSeekBalanceSettings(
            fullBalance: defaults.object(forKey: self.deepSeekBalanceThresholdKey) == nil
                ? self.defaultDeepSeekBalanceThreshold : defaults.double(forKey: self.deepSeekBalanceThresholdKey),
            warningPercent: defaults.object(forKey: self.deepSeekWarningPercentKey) == nil
                ? self.defaultDeepSeekWarningPercent : defaults.double(forKey: self.deepSeekWarningPercentKey)
        )
    }

    // MARK: - Claude

    static let claudeSessionCookieKey = "claudeSessionCookie"

    static var claudeSessionCookie: String {
        get { UserDefaults.standard.string(forKey: self.claudeSessionCookieKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: self.claudeSessionCookieKey) }
    }
}
