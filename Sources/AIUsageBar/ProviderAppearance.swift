import AppKit

extension ProviderID {
    func ringColor(override: String?) -> NSColor {
        NSColor(hex: override) ?? NSColor(hex: self.defaultRingColorHex) ?? .white
    }

    func ringColor(in defaults: UserDefaults = .standard) -> NSColor {
        self.ringColor(override: defaults.string(forKey: self.ringColorKey))
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
