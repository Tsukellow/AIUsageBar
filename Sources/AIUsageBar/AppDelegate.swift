import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let codexModel = AppModel()
    let claudeModel = ClaudeModel()
    let deepSeekModel = DeepSeekModel()
    let antigravityModel = AntigravityModel()
    let grokModel = GrokModel()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var popover = Self.makeUsagePopover(content: CombinedMenuContentView(
        claudeModel: self.claudeModel,
        codexModel: self.codexModel,
        deepSeekModel: self.deepSeekModel,
        antigravityModel: self.antigravityModel,
        grokModel: self.grokModel,
        openSettings: { [weak self] in self?.openSettingsWindow() }
    ))
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=true in Info.plist sets the activation policy before launch.
        // Programmatic fallback in case the Info.plist isn't embedded (e.g. plain `swift run`).
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        self.configureStatusItem()
        self.bindStatusItemUpdates()
        self.updateStatusItemImage()
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("AI Usage Bar")

        let clickView = StatusItemClickView { [weak self] in
            self?.togglePopoverFromStatusItem()
        }
        clickView.frame = button.bounds
        clickView.autoresizingMask = [.width, .height]
        button.addSubview(clickView)
    }

    private func bindStatusItemUpdates() {
        // Settings changes redraw the cached data without making a network request.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItemImage()
                }
            }
            .store(in: &self.cancellables)

        self.claudeModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItemImage()
                }
            }
            .store(in: &self.cancellables)

        self.codexModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItemImage()
                }
            }
            .store(in: &self.cancellables)

        Publishers.Merge3(self.deepSeekModel.objectWillChange, self.antigravityModel.objectWillChange, self.grokModel.objectWillChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateStatusItemImage()
                }
            }
            .store(in: &self.cancellables)
    }

    private func updateStatusItemImage() {
        let enabled = Set([
            self.claudeModel.isEnabled ? ProviderID.claude : nil,
            self.codexModel.isEnabled ? .codex : nil,
            self.deepSeekModel.isEnabled ? .deepSeek : nil,
            self.antigravityModel.isEnabled ? .antigravity : nil,
            self.grokModel.isEnabled ? .grok : nil,
        ].compactMap { $0 })
        let hasThirdParty = self.antigravityModel.snapshot?.windows.contains { $0.pool == .thirdParty } ?? false
        let services = MenuBarMeter.visibleMeters(enabled: enabled, hasAntigravityThirdPartyQuota: hasThirdParty).map { meter in
            switch meter {
            case .provider(let provider):
                self.iconData(for: provider)
            case .antigravityThirdParty:
                self.antigravityIconData(windows: self.antigravityModel.menuThirdParty, color: RingAppearance.antigravityThirdParty.color())
            }
        }
        self.statusItem.button?.image = services.isEmpty
            ? NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "AI Usage Bar")
            : MenuBarIconView(services: services, showsNumbers: AppSettings.showMenuBarNumbers()).renderedImage()
    }

    private func iconData(for provider: ProviderID) -> ServiceIconData {
        switch provider {
        case .claude:
            let snapshot = self.claudeModel.errorMessage == nil ? self.claudeModel.snapshot : nil
            return .claude(fiveHour: snapshot?.fiveHour?.remainingPercent,
                           weekly: snapshot?.sevenDay?.remainingPercent, ringColor: provider.ringColor())
        case .codex:
            let limits = self.codexModel.errorMessage == nil ? self.codexModel.snapshot?.rateLimits : nil
            return .codex(rateLimits: limits, ringColor: provider.ringColor())
        case .antigravity:
            return self.antigravityIconData(windows: self.antigravityModel.menuGemini, color: provider.ringColor())
        case .grok:
            return .grok(weekly: self.grokModel.snapshot?.weeklyWindow, ringColor: provider.ringColor())
        case .deepSeek:
            let snapshot = self.deepSeekModel.errorMessage == nil ? self.deepSeekModel.snapshot : nil
            return .deepSeek(balance: snapshot?.balance, todayCost: snapshot?.todayCost,
                             settings: AppSettings.deepSeekBalanceSettings(), ringColor: provider.ringColor())
        }
    }

    private func antigravityIconData(windows: AntigravityQuotaSnapshot.MenuWindows, color: NSColor?) -> ServiceIconData {
        .antigravity(windows: windows, isStale: self.antigravityModel.isStale, ringColor: color)
    }

    private func togglePopoverFromStatusItem() {
        guard let button = self.statusItem.button else {
            return
        }
        self.togglePopover(relativeTo: button)
    }

    private func togglePopover(relativeTo button: NSStatusBarButton) {
        if self.popover.isShown {
            self.popover.performClose(button)
        } else {
            Self.fitUsagePopover(self.popover)
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static let usagePopoverWidth: CGFloat = 300

    static func makeUsagePopover(content: some View) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        let root = content
            .frame(width: self.usagePopoverWidth)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak popover] height in
                if let popover { self.setUsagePopoverHeight(height, on: popover) }
            }
        let controller = NSHostingController(rootView: AnyView(root))
        controller.sizingOptions = []
        popover.contentViewController = controller
        self.fitUsagePopover(popover)
        return popover
    }

    private static func fitUsagePopover(_ popover: NSPopover) {
        guard let controller = popover.contentViewController as? NSHostingController<AnyView> else { return }
        let size = controller.sizeThatFits(in: NSSize(width: self.usagePopoverWidth, height: .infinity))
        self.setUsagePopoverHeight(size.height, on: popover)
    }

    private static func setUsagePopoverHeight(_ height: CGFloat, on popover: NSPopover) {
        guard height.isFinite, height > 0 else { return }
        let size = NSSize(width: self.usagePopoverWidth, height: height.rounded(.up))
        if popover.contentSize != size { popover.contentSize = size }
    }

    private func openSettingsWindow() {
        if self.popover.isShown {
            self.popover.performClose(nil)
        }

        if let window = self.settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(model: self.codexModel, claudeModel: self.claudeModel, deepSeekModel: self.deepSeekModel,
                                        antigravityModel: self.antigravityModel, grokModel: self.grokModel)
        let window = Self.makeSettingsWindow(content: settingsView)
        window.center()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.settingsWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }

        self.settingsWindow = window
    }

    static func makeSettingsWindow(content: SettingsView) -> NSWindow {
        let settingsWindowSize = NSSize(width: 740, height: 670)
        let hostingController = NSHostingController(rootView: content)
        // The resizable window owns its bounds, not the current SwiftUI page.
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsWindowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 700, height: 420)
        window.setContentSize(settingsWindowSize)
        window.title = "AI Usage Bar Settings"
        window.isReleasedWhenClosed = false
        return window
    }
}

private final class StatusItemClickView: NSView {
    let onActivate: () -> Void
    private var lastClickTimestamp: TimeInterval = 0

    init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            self.handleRightEquivalentClick()
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            self.handleRightEquivalentClick()
        } else {
            self.handlePrimaryClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        self.handleRightEquivalentClick()
    }

    override func rightMouseUp(with event: NSEvent) {
        self.handleRightEquivalentClick()
    }

    override func otherMouseDown(with event: NSEvent) {
        self.handleRightEquivalentClick()
    }

    override func otherMouseUp(with event: NSEvent) {
        self.handleRightEquivalentClick()
    }

    private func handlePrimaryClick() {
        guard self.shouldHandleClick() else {
            return
        }
        self.onActivate()
    }

    private func handleRightEquivalentClick() {
        guard self.shouldHandleClick() else {
            return
        }
        self.onActivate()
    }

    private func shouldHandleClick() -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - self.lastClickTimestamp > 0.15 else {
            return false
        }
        self.lastClickTimestamp = now
        return true
    }
}
