import AppKit
import SwiftUI

// MARK: - Helpers

struct EnumPicker<T: TitledEnum>: View {
    let title: String
    @Binding var value: T
    var body: some View {
        Picker(title, selection: $value) {
            ForEach(Array(T.allCases), id: \.self) { Text($0.title).tag($0) }
        }
    }
}

struct OptionalEnumPicker<T: TitledEnum>: View {
    let title: String
    @Binding var value: T?
    var body: some View {
        Picker(title, selection: $value) {
            Text("Same as global").tag(T?.none)
            ForEach(Array(T.allCases), id: \.self) { Text($0.title).tag(T?.some($0)) }
        }
    }
}

struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: Shortcut
    var mode: RecorderMode = .keyOnly
    var body: some View {
        LabeledContent(title) { ShortcutRecorder(shortcut: $shortcut, mode: mode) }
    }
}

// MARK: - Root

struct SettingsRoot: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ControlsTab().tabItem { Label("Controls", systemImage: "keyboard") }
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintbrush") }
            ExceptionsTab().tabItem { Label("Exceptions", systemImage: "nosign") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 660, height: 600)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var store = SettingsStore.shared
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow("Accessibility", granted: accessibility,
                              detail: "Required to catch the shortcut and raise windows.",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                permissionRow("Screen Recording", granted: screenRecording,
                              detail: "Required for window thumbnails and titles. Relaunch after granting.",
                              url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }
            Section("Startup") {
                Toggle("Start at login", isOn: $store.s.startAtLogin)
            }
            Section("Menu bar") {
                Toggle("Show menu bar icon", isOn: $store.s.menubarIconShown)
                EnumPicker(title: "Icon style", value: $store.s.menubarIcon)
                    .disabled(!store.s.menubarIconShown)
                if !store.s.menubarIconShown {
                    Text("With the icon hidden, relaunch the app to open these settings again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Reset all settings to defaults", role: .destructive) { store.reset() }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionRow(_ name: String, granted: Bool, detail: String, url: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings") { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
            }
        }
    }
}

// MARK: - Controls

struct ControlsTab: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        Form {
            ForEach($store.s.triggers) { $t in
                let index = (store.s.triggers.firstIndex { $0.id == t.id } ?? 0) + 1
                Section {
                    ShortcutRow(title: "Hold", shortcut: $t.hold, mode: .modifiersOnly)
                    ShortcutRow(title: "Then press", shortcut: $t.next)
                    EnumPicker(title: "Apps to show", value: $t.appsToShow)
                    EnumPicker(title: "Spaces to show", value: $t.spacesToShow)
                    EnumPicker(title: "Screens to show", value: $t.screensToShow)
                    EnumPicker(title: "Minimized windows", value: $t.showMinimized)
                    EnumPicker(title: "Hidden apps' windows", value: $t.showHidden)
                    EnumPicker(title: "Fullscreen windows", value: $t.showFullscreen)
                    EnumPicker(title: "Apps without windows", value: $t.showWindowless)
                    EnumPicker(title: "Order", value: $t.order)
                    EnumPicker(title: "Grouping", value: $t.groupApps)
                    EnumPicker(title: "When releasing the keys", value: $t.shortcutStyle)
                    DisclosureGroup("Appearance override") {
                        OptionalEnumPicker(title: "Style", value: $t.styleOverride)
                        OptionalEnumPicker(title: "Size", value: $t.sizeOverride)
                        OptionalEnumPicker(title: "Theme", value: $t.themeOverride)
                    }
                } header: {
                    HStack {
                        Text("Shortcut \(index)")
                        Spacer()
                        if store.s.triggers.count > 1 {
                            Button(role: .destructive) {
                                store.s.triggers.removeAll { $0.id == t.id }
                            } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            if store.s.triggers.count < 9 {
                Section {
                    Button("Add shortcut") {
                        store.s.triggers.append(Trigger(next: Shortcut(keyCode: 48), appsToShow: .all))
                    }
                }
            }

            Section("While the switcher is open") {
                ShortcutRow(title: "Focus selected window", shortcut: $store.s.focusKey)
                ShortcutRow(title: "Previous window (modifier or key)", shortcut: $store.s.previousKey, mode: .keyOnly)
                ShortcutRow(title: "Cancel", shortcut: $store.s.cancelKey)
                ShortcutRow(title: "Close window", shortcut: $store.s.closeKey)
                ShortcutRow(title: "Minimize / restore window", shortcut: $store.s.minimizeKey)
                ShortcutRow(title: "Toggle fullscreen", shortcut: $store.s.fullscreenKey)
                ShortcutRow(title: "Quit app", shortcut: $store.s.quitKey)
                ShortcutRow(title: "Hide / show app", shortcut: $store.s.hideKey)
                ShortcutRow(title: "Search", shortcut: $store.s.searchKey)
                ShortcutRow(title: "Mission Control: next window of app", shortcut: $store.s.subSelectKey)
                ShortcutRow(title: "Mission Control: expand / collapse app", shortcut: $store.s.expandKey)
                Toggle("Arrow keys select windows", isOn: $store.s.arrowKeys)
                Toggle("Vim keys (H J K L) select windows", isOn: $store.s.vimKeys)
            }

            Section("Mouse & timing") {
                Toggle("Select windows by hovering", isOn: $store.s.mouseHover)
                EnumPicker(title: "Move cursor to focused window", value: $store.s.cursorFollow)
                Stepper("Show switcher after \(store.s.displayDelayMs) ms",
                        value: $store.s.displayDelayMs, in: 0...1000, step: 25)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        Form {
            Section("Layout") {
                EnumPicker(title: "Style", value: $store.s.style)
                EnumPicker(title: "Size", value: $store.s.size)
                EnumPicker(title: "Theme", value: $store.s.theme)
                EnumPicker(title: "Show on", value: $store.s.showOnScreen)
            }
            Section("Titles") {
                EnumPicker(title: "Show", value: $store.s.showTitles)
                EnumPicker(title: "Truncate at", value: $store.s.truncation)
            }
            Section("Mission Control style") {
                LabeledContent("Zoom a group while scrolling over it") {
                    HStack {
                        Slider(value: $store.s.groupZoom, in: 1...3, step: 0.1).frame(width: 180)
                        Text(store.s.groupZoom <= 1.01 ? "Off" : String(format: "%.1f×", store.s.groupZoom))
                            .monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Section("Details") {
                Toggle("Hide status icons (minimized, hidden, fullscreen)", isOn: $store.s.hideStatusIcons)
                Toggle("Hide Space numbers", isOn: $store.s.hideSpaceLabels)
                Toggle("Hide close / minimize / fullscreen buttons", isOn: $store.s.hideTrafficLights)
            }
            Section("Preview & animation") {
                Toggle("Preview the selected window", isOn: $store.s.previewSelectedWindow)
                Toggle("Fade in the preview", isOn: $store.s.previewFadeIn)
                    .disabled(!store.s.previewSelectedWindow)
                Toggle("Fade out the switcher", isOn: $store.s.fadeOut)
                Toggle("Keep thumbnails fresh in the background", isOn: $store.s.captureInBackground)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Exceptions

struct ExceptionsTab: View {
    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if store.s.exceptions.isEmpty {
                    Text("No exceptions yet. Add an app to hide it from the switcher or to let it keep its own shortcuts.")
                        .foregroundStyle(.secondary)
                }
                ForEach($store.s.exceptions) { $e in
                    Section {
                        EnumPicker(title: "Hide from switcher", value: $e.hide)
                        if e.hide == .titleContains {
                            TextField("Title contains", text: $e.titleContains)
                        }
                        EnumPicker(title: "Shortcuts", value: $e.ignore)
                    } header: {
                        HStack {
                            Text(e.name)
                            Spacer()
                            Button(role: .destructive) {
                                store.s.exceptions.removeAll { $0.id == e.id }
                            } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Add app…", action: chooseApp)
                Menu("Add running app") {
                    ForEach(runningApps(), id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(bundleID: app.bundleIdentifier, name: app.localizedName) }
                    }
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url) else { return }
        add(bundleID: bundle.bundleIdentifier,
            name: (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent)
    }

    private func add(bundleID: String?, name: String?) {
        guard let bundleID, !store.s.exceptions.contains(where: { $0.bundleID == bundleID }) else { return }
        store.s.exceptions.append(ExceptionEntry(bundleID: bundleID, name: name ?? bundleID, hide: .always))
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Window Switcher").font(.title)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("A window switcher for macOS inspired by AltTab.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Window controller

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsRoot()))
            w.title = "Window Switcher Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
