import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Remembers when each window was last focused / created so windows can be ordered most-recently-used.
final class FocusTracker {
    static let shared = FocusTracker()

    private(set) var focus: [CGWindowID: Double] = [:]
    private(set) var created: [CGWindowID: Double] = [:]
    private(set) var appFocus: [pid_t: Double] = [:]
    private var observers: [pid_t: AXObserver] = [:]

    private static let notifications = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification,
    ]

    func start() {
        // Seed from the current stacking order so the first switch already has a sensible MRU.
        let now = Date.timeIntervalSinceReferenceDate
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for (i, info) in infos.enumerated() {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            focus[id] = now - Double(i) - 1
            created[id] = now - Double(i) - 1
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.observe(app) }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observers[app.processIdentifier] = nil
            }
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appFocus[app.processIdentifier] = Date.timeIntervalSinceReferenceDate
            self?.recordFocusedWindow(of: app.processIdentifier)
        }
        ensureObservers()
    }

    /// Safe to call repeatedly; needed because Accessibility may be granted after launch.
    func ensureObservers() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications { observe(app) }
    }

    func record(_ id: CGWindowID) { focus[id] = Date.timeIntervalSinceReferenceDate }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, observers[pid] == nil, !app.isTerminated else { return }
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            let me = Unmanaged<FocusTracker>.fromOpaque(refcon!).takeUnretainedValue()
            me.handle(element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.notifications { AXObserverAddNotification(obs, appElement, n as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func handle(_ element: AXUIElement, _ notification: String) {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return }
        let now = Date.timeIntervalSinceReferenceDate
        if notification == kAXWindowCreatedNotification { created[id] = now }
        focus[id] = now
    }

    private func recordFocusedWindow(of pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value else { return }
        var id: CGWindowID = 0
        if _AXUIElementGetWindow(value as! AXUIElement, &id) == .success, id != 0 { record(id) }
    }
}
