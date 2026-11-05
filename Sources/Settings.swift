import AppKit
import Combine

extension Notification.Name {
    static let settingsChanged = Notification.Name("WindowSwitcher.settingsChanged")
}

protocol TitledEnum: CaseIterable, Hashable, Codable {
    var title: String { get }
}

// MARK: - Enumerations

enum ShowHow: String, TitledEnum {
    case show, hide, showAtEnd
    var title: String { ["show": "Show", "hide": "Hide", "showAtEnd": "Show at the end"][rawValue]! }
}

enum WindowOrder: String, TitledEnum {
    case recentlyFocused, recentlyCreated, alphabetical, space
    var title: String {
        ["recentlyFocused": "Recently focused first", "recentlyCreated": "Recently created first",
         "alphabetical": "Alphabetical (app, then title)", "space": "By Space"][rawValue]!
    }
}

enum AppsToShow: String, TitledEnum {
    case all, active, nonActive
    var title: String { ["all": "All apps", "active": "Active app only", "nonActive": "Non-active apps"][rawValue]! }
}

enum SpacesToShow: String, TitledEnum {
    case all, visible, nonVisible
    var title: String { ["all": "All Spaces", "visible": "Visible Spaces", "nonVisible": "Non-visible Spaces"][rawValue]! }
}

enum ScreensToShow: String, TitledEnum {
    case all, showingSwitcher
    var title: String { ["all": "All screens", "showingSwitcher": "Screen showing the switcher"][rawValue]! }
}

enum ShowOnScreen: String, TitledEnum {
    case active, mouse, menubar
    var title: String {
        ["active": "Active screen", "mouse": "Screen containing the mouse", "menubar": "Screen with the menu bar"][rawValue]!
    }
}

enum TitleTruncation: String, TitledEnum {
    case start, middle, end
    var title: String { rawValue.capitalized }
    var mode: NSLineBreakMode {
        switch self {
        case .start: return .byTruncatingHead
        case .middle: return .byTruncatingMiddle
        case .end: return .byTruncatingTail
        }
    }
}

enum ShowTitles: String, TitledEnum {
    case windowTitle, appName, appNameAndWindowTitle
    var title: String {
        ["windowTitle": "Window title", "appName": "App name", "appNameAndWindowTitle": "App name and window title"][rawValue]!
    }
}

enum AppearanceStyle: String, TitledEnum {
    case missionControl, thumbnails, appIcons, titles
    var title: String {
        ["missionControl": "Mission Control (grouped by app)", "thumbnails": "Thumbnails",
         "appIcons": "App icons", "titles": "Titles"][rawValue]!
    }
}

enum AppearanceSize: String, TitledEnum {
    case small, medium, large, auto
    var title: String { rawValue.capitalized }
}

enum AppearanceTheme: String, TitledEnum {
    case light, dark, system
    var title: String { rawValue.capitalized }
}

enum GroupApps: String, TitledEnum {
    case allWindows, mainWindow
    var title: String { rawValue == "allWindows" ? "Show every window" : "Show one window per app" }
}

enum ShortcutStyle: String, TitledEnum {
    case focusOnRelease, doNothingOnRelease, searchOnRelease
    var title: String {
        ["focusOnRelease": "Focus selected window", "doNothingOnRelease": "Keep open (confirm with Return)",
         "searchOnRelease": "Start searching"][rawValue]!
    }
}

enum CursorFollow: String, TitledEnum {
    case never, always, differentScreen
    var title: String {
        ["never": "Never", "always": "Always", "differentScreen": "Only when changing screen"][rawValue]!
    }
}

enum MenubarIconStyle: String, TitledEnum {
    case outlined, filled
    var title: String { rawValue.capitalized }
}

enum ExceptionHide: String, TitledEnum {
    case none, always, noWindows, titleContains
    var title: String {
        ["none": "Don't hide", "always": "Always hide", "noWindows": "Hide when it has no window",
         "titleContains": "Hide windows whose title contains…"][rawValue]!
    }
}

enum ExceptionIgnore: String, TitledEnum {
    case none, always, whenFullscreen
    var title: String {
        ["none": "Don't ignore", "always": "Always ignore shortcuts", "whenFullscreen": "Ignore shortcuts when fullscreen"][rawValue]!
    }
}

// MARK: - Shortcut

struct Shortcut: Codable, Equatable {
    var keyCode: Int = -1
    var modifiers: UInt = 0

    static let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: Int = -1, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantMask).rawValue
    }

    var hasKey: Bool { keyCode >= 0 }
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var isEmpty: Bool { !hasKey && modifiers == 0 }

    var display: String {
        if isEmpty { return "—" }
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        if hasKey { s += Self.keyNames[keyCode] ?? "key \(keyCode)" }
        return s
    }

    static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
        49: "Space", 50: "`", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]
}

// MARK: - Trigger (one hold+next shortcut with its own filters)

struct Trigger: Codable, Equatable, Identifiable {
    var id = UUID()
    var hold = Shortcut(modifiers: .option)
    var next = Shortcut(keyCode: 48)
    var appsToShow: AppsToShow = .all
    var spacesToShow: SpacesToShow = .all
    var screensToShow: ScreensToShow = .all
    var showMinimized: ShowHow = .show
    var showHidden: ShowHow = .show
    var showFullscreen: ShowHow = .show
    var showWindowless: ShowHow = .showAtEnd
    var order: WindowOrder = .recentlyFocused
    var groupApps: GroupApps = .allWindows
    var shortcutStyle: ShortcutStyle = .focusOnRelease
    var styleOverride: AppearanceStyle?
    var sizeOverride: AppearanceSize?
    var themeOverride: AppearanceTheme?
}

struct ExceptionEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var bundleID: String
    var name: String
    var hide: ExceptionHide = .none
    var titleContains: String = ""
    var ignore: ExceptionIgnore = .none
}

// MARK: - Settings

struct Settings: Codable, Equatable {
    var triggers: [Trigger] = [
        Trigger(),
        Trigger(next: Shortcut(keyCode: 50), appsToShow: .active),
    ]

    // In-switcher keys
    var focusKey = Shortcut(keyCode: 36)
    var previousKey = Shortcut(modifiers: .shift)
    var cancelKey = Shortcut(keyCode: 53)
    var closeKey = Shortcut(keyCode: 13)
    var minimizeKey = Shortcut(keyCode: 46)
    var fullscreenKey = Shortcut(keyCode: 3)
    var quitKey = Shortcut(keyCode: 12)
    var hideKey = Shortcut(keyCode: 4)
    var searchKey = Shortcut(keyCode: 1)
    var subSelectKey = Shortcut(keyCode: 50)   // Mission Control style: cycle windows of the selected app
    var expandKey = Shortcut(keyCode: 49)      // Mission Control style: expand/collapse the selected app

    var arrowKeys = true
    var vimKeys = false
    var mouseHover = true
    var cursorFollow: CursorFollow = .never
    var hideTrafficLights = false
    var groupZoom = 1.6   // Mission Control: scale of a group while scrolling over it (1 = off)
    var displayDelayMs = 100

    var style: AppearanceStyle = .missionControl
    var size: AppearanceSize = .auto
    var theme: AppearanceTheme = .system
    var showOnScreen: ShowOnScreen = .active
    var truncation: TitleTruncation = .end
    var showTitles: ShowTitles = .windowTitle
    var fadeOut = false
    var previewFadeIn = true
    var hideSpaceLabels = true
    var hideStatusIcons = false
    var previewSelectedWindow = false
    var captureInBackground = true

    var startAtLogin = false
    var menubarIcon: MenubarIconStyle = .outlined
    var menubarIconShown = true

    var exceptions: [ExceptionEntry] = []
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static let key = "settings"

    @Published var s: Settings {
        didSet {
            guard s != oldValue else { return }
            if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    private init() { s = Self.load() }

    func reset() { s = Settings() }

    /// Stored values are overlaid on the defaults so settings added in newer versions keep their defaults.
    private static func load() -> Settings {
        let defaults = Settings()
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(stored) { _, new in new }),
              let decoded = try? JSONDecoder().decode(Settings.self, from: merged)
        else { return defaults }
        return decoded
    }
}
