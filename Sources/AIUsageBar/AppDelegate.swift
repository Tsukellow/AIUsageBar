import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let codexModel = AppModel()
    let claudeModel = ClaudeModel()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=true in Info.plist sets the activation policy before launch.
        // Programmatic fallback in case the Info.plist isn't embedded (e.g. plain `swift run`).
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        self.configurePopover()
        self.configureStatusItem()
        self.bindStatusItemUpdates()
        self.updateStatusItemImage()
    }

    private func configurePopover() {
        self.popover.behavior = .transient
        let controller = NSHostingController(
            rootView: CombinedMenuContentView(
                claudeModel: self.claudeModel,
                codexModel: self.codexModel,
                openSettings: { [weak self] in
                    self?.openSettingsWindow()
                }
            )
        )
        self.popover.contentViewController = controller
        self.popover.contentSize = NSSize(width: 300, height: 360)
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else {
            return
        }

        button.imagePosition = .imageOnly

        let clickView = StatusItemClickView { [weak self] in
            self?.togglePopoverFromStatusItem()
        }
        clickView.frame = button.bounds
        clickView.autoresizingMask = [.width, .height]
        button.addSubview(clickView)
    }

    private func bindStatusItemUpdates() {
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
    }

    private func updateStatusItemImage() {
        var services: [ServiceIconData] = []

        if self.claudeModel.isEnabled {
            services.append(ServiceIconData(
                ringFraction: self.claudeModel.menuBarFiveHourRemainingFraction,
                topText: self.claudeModel.menuBarFiveHourRemainingText,
                bottomText: self.claudeModel.menuBarWeeklyRemainingText,
                ringColor: NSColor(red: 0.85, green: 0.45, blue: 0.34, alpha: 1.0)
            ))
        }

        if self.codexModel.isEnabled {
            services.append(ServiceIconData(
                ringFraction: self.codexModel.menuBarFiveHourRemainingFraction,
                topText: self.codexModel.menuBarFiveHourRemainingText,
                bottomText: self.codexModel.menuBarWeeklyRemainingText,
                ringColor: NSColor.white
            ))
        }

        self.statusItem.button?.image = services.isEmpty
            ? nil
            : MenuBarIconView(services: services).renderedImage()
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
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
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

        let settingsWindowSize = NSSize(width: 450, height: 450)
        let settingsView = SettingsView(model: self.codexModel, claudeModel: self.claudeModel)
        let hostingController = NSHostingController(
            rootView: settingsView.frame(width: settingsWindowSize.width, height: settingsWindowSize.height)
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: settingsWindowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "AI Usage Bar Settings"
        window.isReleasedWhenClosed = false
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
