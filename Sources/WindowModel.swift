import AppKit
import ApplicationServices

final class Win {
    let id: CGWindowID
    let pid: pid_t
    var title: String
    let app: NSRunningApplication
    let appName: String
    let bundleID: String?
    let icon: NSImage
    var bounds: CGRect = .zero
    var isMinimized = false
    var isHidden = false
    var isFullscreen = false
    let isWindowless: Bool
    var onVisibleSpace = true
    var spaceNumber: Int?
    var displayID: CGDirectDisplayID = 0
    var lastFocus: Double = 0
    var created: Double = 0
    var thumbnail: NSImage?

    init(id: CGWindowID, pid: pid_t, title: String, app: NSRunningApplication, isWindowless: Bool = false) {
        self.id = id
        self.pid = pid
        self.title = title
        self.app = app
        self.isWindowless = isWindowless
        appName = app.localizedName ?? "App"
        bundleID = app.bundleIdentifier
        icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    func displayTitle(_ mode: ShowTitles) -> String {
        if isWindowless { return appName }
        switch mode {
        case .windowTitle: return title.isEmpty ? appName : title
        case .appName: return appName
        case .appNameAndWindowTitle: return title.isEmpty ? appName : "\(appName) — \(title)"
        }
    }
}

enum Screens {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
    }

    static func target(for pref: ShowOnScreen) -> NSScreen {
        let screens = NSScreen.screens
        switch pref {
        case .mouse:
            return screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens[0]
        case .menubar:
            return screens[0]
        case .active:
            return NSScreen.main ?? screens[0]
        }
    }
}

enum WindowProvider {
    private struct AXState {
        var minimized: Bool
        var fullscreen: Bool
    }

    /// Windows the given trigger should list, in display order.
    static func windows(for trigger: Trigger, settings: Settings, display: CGDirectDisplayID) -> [Win] {
        var wins = allWindows()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Exceptions
        wins = wins.filter { w in
            guard let ex = settings.exceptions.first(where: { $0.bundleID == w.bundleID }) else { return true }
            switch ex.hide {
            case .none: return true
            case .always: return false
            case .noWindows: return !w.isWindowless
            case .titleContains:
                return ex.titleContains.isEmpty || w.isWindowless
                    || !w.title.localizedCaseInsensitiveContains(ex.titleContains)
            }
        }

        wins = wins.filter { w in
            switch trigger.appsToShow {
            case .all: break
            case .active: if w.pid != front { return false }
            case .nonActive: if w.pid == front { return false }
            }
            if w.isWindowless { return true }
            switch trigger.spacesToShow {
            case .all: break
            case .visible: if !w.onVisibleSpace { return false }
            case .nonVisible: if w.onVisibleSpace { return false }
            }
            if trigger.screensToShow == .showingSwitcher && w.displayID != display { return false }
            if w.isMinimized && trigger.showMinimized == .hide { return false }
            if w.isHidden && trigger.showHidden == .hide { return false }
            if w.isFullscreen && trigger.showFullscreen == .hide { return false }
            return true
        }
        wins = wins.filter { !$0.isWindowless || trigger.showWindowless != .hide }

        wins = ordered(wins, by: trigger.order)

        if trigger.groupApps == .mainWindow {
            var seen = Set<pid_t>()
            wins = wins.filter { seen.insert($0.pid).inserted }
        }

        // "Show at the end" partitions, keeping relative order.
        func atEnd(_ w: Win) -> Bool {
            (w.isMinimized && trigger.showMinimized == .showAtEnd)
                || (w.isHidden && trigger.showHidden == .showAtEnd)
                || (w.isFullscreen && trigger.showFullscreen == .showAtEnd)
                || (w.isWindowless && trigger.showWindowless == .showAtEnd)
        }
        return wins.filter { !atEnd($0) } + wins.filter(atEnd)
    }

    private static func ordered(_ wins: [Win], by order: WindowOrder) -> [Win] {
        switch order {
        case .recentlyFocused:
            return wins.sorted { $0.lastFocus > $1.lastFocus }
        case .recentlyCreated:
            return wins.sorted { $0.created > $1.created }
        case .alphabetical:
            return wins.sorted {
                let c = $0.appName.localizedCaseInsensitiveCompare($1.appName)
                return c == .orderedSame ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : c == .orderedAscending
            }
        case .space:
            return wins.sorted {
                let a = $0.spaceNumber ?? Int.max, b = $1.spaceNumber ?? Int.max
                return a == b ? $0.lastFocus > $1.lastFocus : a < b
            }
        }
    }

    /// Every window the system knows about that looks like a user-facing window, plus windowless apps.
    static func allWindows() -> [Win] {
        let tracker = FocusTracker.shared
        let spaces = PrivateAPI.spaceInfo()
        let axTrusted = AXIsProcessTrusted()
        let me = getpid()
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        var apps: [pid_t: NSRunningApplication?] = [:]
        var axCache: [pid_t: [CGWindowID: AXState]?] = [:]
        var out: [Win] = []
        var pidsWithWindows = Set<pid_t>()

        for (z, info) in infos.enumerated() {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }

            let app: NSRunningApplication?
            if let cached = apps[pid] { app = cached } else {
                app = NSRunningApplication(processIdentifier: pid)
                apps[pid] = app
            }
            guard let app, app.activationPolicy == .regular else { continue }

            let onScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let title = info[kCGWindowName as String] as? String ?? ""
            let winSpaces = PrivateAPI.spaces(of: id)
            let visibleSpace = winSpaces.isEmpty || !spaces.visible.isDisjoint(with: winSpaces)

            var ax: AXState?
            var axKnown = false
            if axTrusted {
                if axCache[pid] == nil { axCache[pid] = .some(axStates(pid: pid)) }
                if let states = axCache[pid] ?? nil {
                    axKnown = !states.isEmpty
                    ax = states[id]
                }
            }

            let include: Bool
            if axTrusted {
                if ax != nil { include = true }
                else if !visibleSpace { include = !title.isEmpty }       // other Space: AX can't see it
                else { include = onScreen && !axKnown }                  // app without usable AX windows
            } else {
                include = onScreen || !title.isEmpty
            }
            guard include else { continue }

            let w = Win(id: id, pid: pid, title: title, app: app)
            w.bounds = bounds
            w.isMinimized = ax?.minimized ?? false
            w.isFullscreen = (ax?.fullscreen ?? false) || !spaces.fullscreen.isDisjoint(with: winSpaces)
            w.isHidden = app.isHidden
            w.onVisibleSpace = visibleSpace
            w.spaceNumber = winSpaces.compactMap { spaces.numbers[$0] }.min()
            w.displayID = display(for: bounds)
            w.lastFocus = tracker.focus[id] ?? -Double(z)
            w.created = tracker.created[id] ?? -Double(z)
            w.thumbnail = ThumbnailCache.shared.image(for: id)
            out.append(w)
            pidsWithWindows.insert(pid)
        }

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != me
            && !pidsWithWindows.contains(app.processIdentifier) {
            let w = Win(id: 0, pid: app.processIdentifier, title: "", app: app, isWindowless: true)
            w.isHidden = app.isHidden
            w.lastFocus = tracker.appFocus[app.processIdentifier] ?? 0
            out.append(w)
        }
        return out
    }

    private static func display(for bounds: CGRect) -> CGDirectDisplayID {
        var did = CGDirectDisplayID()
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: bounds.midX, y: bounds.midY), 1, &did, &count)
        return count > 0 ? did : CGMainDisplayID()
    }

    /// AX windows of an app keyed by window id; nil when the app can't be queried.
    private static func axStates(pid: pid_t) -> [CGWindowID: AXState]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let wins = value as? [AXUIElement] else { return nil }
        var result: [CGWindowID: AXState] = [:]
        for w in wins {
            var id: CGWindowID = 0
            guard _AXUIElementGetWindow(w, &id) == .success, id != 0 else { continue }
            if let sub: String = attr(w, kAXSubroleAttribute),
               sub != kAXStandardWindowSubrole, sub != kAXDialogSubrole { continue }
            let minimized: Bool = attr(w, kAXMinimizedAttribute) ?? false
            let fullscreen: Bool = attr(w, "AXFullScreen") ?? false
            result[id] = AXState(minimized: minimized, fullscreen: fullscreen)
        }
        return result
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
}
