import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let switcher = Switcher()
    private lazy var tap = HotkeyTap(switcher: switcher)
    private let settingsWindow = SettingsWindowController()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var nativeTabDisabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        FocusTracker.shared.start()
        applySettings()
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        }
        observeBackgroundCapture()

        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        if !trusted || !CGPreflightScreenCaptureAccess() { settingsWindow.show() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            self.tap.install()
            FocusTracker.shared.ensureObservers()
        }
        timer?.fire()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if nativeTabDisabled { PrivateAPI.setNativeCommandTab(enabled: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return true
    }

    // MARK: Settings side effects

    private func applySettings() {
        let s = SettingsStore.shared.s

        statusItem.isVisible = s.menubarIconShown
        statusItem.button?.image = Self.menuBarIcon(filled: s.menubarIcon == .filled)
        statusItem.button?.toolTip = "Window Switcher"

        // Take over ⌘Tab only while a shortcut uses it.
        let usesCommandTab = s.triggers.contains { $0.hold.flags == .command && $0.next.keyCode == 48 }
        if usesCommandTab != nativeTabDisabled {
            PrivateAPI.setNativeCommandTab(enabled: !usesCommandTab)
            nativeTabDisabled = usesCommandTab
        }

        let service = SMAppService.mainApp
        if s.startAtLogin, service.status != .enabled { try? service.register() }
        if !s.startAtLogin, service.status == .enabled { try? service.unregister() }
    }

    /// Keeps thumbnails ready: when an app loses focus, snapshot its visible windows.
    private func observeBackgroundCapture() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { n in
            guard SettingsStore.shared.s.captureInBackground, ThumbnailCache.canCapture,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let ids = infos.compactMap { info -> CGWindowID? in
                    guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                          (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }
                    return info[kCGWindowNumber as String] as? CGWindowID
                }
                if !ids.isEmpty { ThumbnailCache.shared.capture(ids) { _, _ in } }
            }
        }
    }

    // MARK: Menu bar

    private static func menuBarIcon(filled: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            for r in [NSRect(x: 1, y: 8, width: 10, height: 7), NSRect(x: 5, y: 4.5, width: 10, height: 7)] {
                let p = NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5)
                if filled { p.fill() } else { p.lineWidth = 1.2; p.stroke() }
            }
            NSBezierPath(roundedRect: NSRect(x: 9, y: 1, width: 10, height: 7), xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Window Switcher"
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = SettingsStore.shared.s
        let status = tap.isInstalled
            ? "Active — " + s.triggers.map { $0.hold.display + $0.next.display }.joined(separator: "  ")
            : "Waiting for Accessibility permission…"
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Window Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action == #selector(openSettings) { item.target = self }
    }

    @objc private func openSettings() { settingsWindow.show() }
}
