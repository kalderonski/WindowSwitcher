# WindowSwitcher

A fast, keyboard-driven **window** switcher for macOS — an alternative to the built-in ⌘Tab that switches between individual windows (not just apps), works across Spaces and screens, and is highly configurable.

It lives in the menu bar (no Dock icon), is written in pure Swift/AppKit/SwiftUI, and has no third-party dependencies.

## Features

- **Window-level switching** – hold a modifier, tap a key, and cycle through every window, ordered by most-recently-used.
- **Four appearance styles** – Mission Control (windows grouped per app, cascaded), Thumbnails, App icons, or Titles.
- **Live thumbnails** captured with ScreenCaptureKit, with an optional full-size preview of the selected window.
- **Multiple triggers** – each with its own shortcut and filters. Defaults:
  - `⌥ Tab` – all windows
  - `⌥ \`` – windows of the active app only
- **Per-trigger filters** – apps (all / active / non-active), Spaces (all / visible / non-visible), screens, minimized, hidden, fullscreen and windowless apps (show / hide / show at end), plus ordering (recently focused, recently created, alphabetical, by Space) and grouping (every window vs. one per app).
- **Per-trigger release behavior** – focus on release, keep open and confirm with Return, or jump into search.
- **Actions on the selected window, from the keyboard** – close, minimize/restore, toggle fullscreen, quit app, hide app, search.
- **Search** – type to filter windows by app or title.
- **Mouse support** – hover to select, click to focus, scroll over an app tile to step through its windows, optional zoom on hover, traffic-light buttons.
- **Vim-style and arrow-key navigation** (optional).
- **Exceptions** – hide or ignore specific apps (always, when windowless, or when a window title contains some text).
- **Works across Spaces** – focuses windows living on other Spaces via private SkyLight/CGS APIs (resolved at runtime, so a missing symbol degrades gracefully).
- **Can replace the native ⌘Tab** – the system switcher can be disabled while WindowSwitcher is running.
- Light / dark / system theme, small / medium / large / auto size, multi-screen placement, cursor-follows-focus, launch at login, menu bar icon styles.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode command line tools (`xcode-select --install`) – provides `swiftc`, `iconutil`, and `codesign`

## Build & install

```bash
git clone https://github.com/kalderonski/WindowSwitcher.git
cd WindowSwitcher

# Optional but recommended, one time: create a stable local code-signing identity
./tools/setup_signing.sh

# Build and install into /Applications, then launch
./install.sh
```

To only build (output: `build/WindowSwitcher.app`):

```bash
./build.sh
```

### Why the signing step?

macOS ties privacy permissions (Accessibility, Screen Recording) to an app's code signature. An ad-hoc signature changes on every build, so permissions would be revoked each time you rebuild. `tools/setup_signing.sh` creates a self-signed identity named **WindowSwitcher Local Signing** in your login keychain; `build.sh` uses it automatically when present. If it's missing, the build falls back to ad-hoc signing and prints a warning.

## Permissions

On first launch, open **Settings → General → Permissions** and grant:

| Permission | Why it's needed |
|---|---|
| **Accessibility** | Listen for the global shortcuts, enumerate windows, and raise/close/minimize them |
| **Screen Recording** | Capture window thumbnails and read window titles |

Grant them under *System Settings → Privacy & Security*, then **relaunch** the app.

## Usage

1. Hold **⌥** and press **⇥** to open the switcher. Keep tapping **⇥** to move forward; hold **⇧** (the default "previous" modifier) to go backward.
2. Release **⌥** to focus the selected window (default release behavior).
3. Use **⌥ \`** to switch only among windows of the current app.

### Keys while the switcher is open (defaults, all rebindable)

| Action | Key |
|---|---|
| Focus selected window | `↩` |
| Previous | `⇧` |
| Cancel / collapse | `⎋` |
| Close window | `W` |
| Minimize / restore | `M` |
| Toggle fullscreen | `F` |
| Quit app | `Q` |
| Hide / show app | `H` |
| Search | `S` |
| Mission Control: next window of selected app | `` ` `` |
| Mission Control: expand / collapse app | `Space` |
| Navigate | arrow keys (and optionally `H J K L`) |

## Settings

Click the menu bar icon → **Settings**. Settings are stored in `UserDefaults` and automatically merged with defaults, so new options added in future versions don't reset your configuration.

- **General** – permissions status, start at login, menu bar icon.
- **Controls** – triggers (hold + key, filters, ordering, release behavior, optional style/size/theme override per trigger), in-switcher keys, arrow/vim keys, mouse hover, cursor-follow, display delay.
- **Appearance** – style, size, theme, which screen to show on, title truncation and content, fade animations, Space labels and status icons, selected-window preview.
- **Exceptions** – per-app rules for hiding or ignoring apps.
- **About**

## Project layout

```
Sources/
  main.swift / AppDelegate.swift   App entry point, menu bar item, lifecycle
  HotkeyTap.swift                  Global CGEvent tap driving the switcher
  Switcher.swift                   Session state machine: selection, search, actions
  WindowModel.swift                Window enumeration, filtering, ordering
  FocusTracker.swift               Tracks MRU focus/creation order
  WindowActions.swift              Focus/close/minimize/etc. and thumbnail capture
  PrivateAPI.swift                 Runtime-resolved SkyLight/CGS calls (Spaces, native ⌘Tab toggle)
  SwitcherPanel.swift              Thumbnails / icons / titles presentation
  MissionPanel.swift               Mission Control style presentation
  Settings.swift                   Settings model and persistence
  SettingsUI.swift                 SwiftUI settings window
  ShortcutRecorder.swift           Shortcut capture control
tools/
  make_icon.swift                  Generates the app icon during build
  setup_signing.sh                 Creates the local signing identity
build.sh                           Compiles, builds the icon, writes Info.plist, signs
install.sh                         Build + install to /Applications + launch
```

## Troubleshooting

- **Shortcuts do nothing / thumbnails missing** – re-check Accessibility and Screen Recording, then relaunch. If you rebuilt without a stable signing identity, remove and re-add the app in the permission lists, or run `tools/setup_signing.sh` and rebuild.
- **Switcher stops responding** – macOS can disable event taps; the app recovers on the next modifier release, but relaunching also fixes it.
- **Windows on other Spaces don't focus** – this relies on private macOS APIs which may change between OS releases.

## Caveats

WindowSwitcher uses undocumented WindowServer/SkyLight APIs for cross-Space focusing and for toggling the native ⌘Tab. These could break in future macOS versions and make the app unsuitable for the Mac App Store. The bundle identifier is the placeholder `com.example.WindowSwitcher`; change it in `build.sh` if you distribute your own build.

## License

No license file is included yet; add one (e.g. MIT) to let others reuse the code.
