import Foundation

enum AppSettings {
    static let refreshIntervalKey = "refreshIntervalSeconds"
    static let initialRefreshDelaySecondsKey = "initialRefreshDelaySeconds"
    static let defaultInitialRefreshDelaySeconds = 60.0

    static var refreshIntervalSeconds: Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: self.refreshIntervalKey) == nil {
            defaults.set(300.0, forKey: self.refreshIntervalKey)
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

    // MARK: - Claude

    static let claudeSessionCookieKey = "claudeSessionCookie"

    static var claudeSessionCookie: String {
        get { UserDefaults.standard.string(forKey: self.claudeSessionCookieKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: self.claudeSessionCookieKey) }
    }
}
