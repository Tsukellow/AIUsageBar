import AppKit

struct RingAppearance {
    let key: String
    let defaultHex: String

    static let antigravityThirdParty = Self(key: "antigravityThirdPartyRingColorHex", defaultHex: "#CF8AC6")

    func color(override: String?) -> NSColor {
        NSColor(hex: override) ?? NSColor(hex: self.defaultHex) ?? .white
    }

    func color(in defaults: UserDefaults = .standard) -> NSColor {
        self.color(override: defaults.string(forKey: self.key))
    }
}

extension ProviderID {
    var ringAppearance: RingAppearance {
        RingAppearance(key: self.ringColorKey, defaultHex: self.defaultRingColorHex)
    }

    func ringColor(override: String?) -> NSColor {
        self.ringAppearance.color(override: override)
    }

    func ringColor(in defaults: UserDefaults = .standard) -> NSColor {
        self.ringAppearance.color(in: defaults)
    }

    func sidebarIconName(dark: Bool) -> String {
        if self == .codex { return dark ? "codex-dark" : "codex-light" }
        return self.rawValue
    }
}

@MainActor
enum ProviderSidebarImages {
    private static let bundled: [String: NSImage] = {
        guard let directory = Bundle.main.resourceURL?.appending(path: "ProviderIcons") else { return [:] }
        let names = Set(ProviderID.allCases.flatMap { [$0.sidebarIconName(dark: false), $0.sidebarIconName(dark: true)] })
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            NSImage(contentsOf: directory.appending(path: name + ".png")).map { (name, $0) }
        })
    }()

    static func image(for provider: ProviderID, dark: Bool) -> NSImage? {
        self.bundled[provider.sidebarIconName(dark: dark)]
    }
}
