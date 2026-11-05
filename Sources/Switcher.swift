import AppKit

/// One switching session: shortcut pressed → list shown → selection moved → focus/cancel.
final class Switcher {
    private let panel = SwitcherPanel()
    private let mission = MissionPanel()
    private let preview = PreviewPanel()

    private var all: [Win] = []
    private var entries: [Win] = []
    private var selected = 0
    private var spaceCount = 0
    private var shown = false
    private var showWork: DispatchWorkItem?
    private var thumbTask: Task<Void, Never>?

    /// Mission Control style: `entries` is kept grouped by app, `groupRanges` are the groups' index ranges.
    private var missionMode = false
    private var groupRanges: [Range<Int>] = []
    private var expanded = false

    private(set) var trigger = Trigger()
    private(set) var active = false
    /// The hold modifiers were released but the session stays open (keep-open / search styles).
    private(set) var released = false
    private(set) var searching = false
    private var query = ""

    private var settings: Settings { SettingsStore.shared.s }
    var isMission: Bool { active && missionMode }
    var isExpanded: Bool { expanded }

    init() {
        panel.onClick = { [weak self] w in
            guard let self, let i = self.entries.firstIndex(where: { $0 === w }) else { return }
            self.selected = i
            self.commit()
        }
        panel.onHover = { [weak self] i in self?.hover(i) }
        panel.onClose = { [weak self] w in self?.close(w) }
        panel.onMinimize = { [weak self] w in self?.minimize(w) }
        panel.onFullscreen = { [weak self] w in self?.fullscreen(w) }
        mission.onClick = { [weak self] i in
            guard let self, self.entries.indices.contains(i) else { return }
            self.selected = i
            self.commit()
        }
        mission.onHover = { [weak self] i in self?.hover(i) }
        mission.onScroll = { [weak self] flat, dir in self?.scrollOver(flat, dir) }
    }

    private func hover(_ i: Int) {
        guard settings.mouseHover, i != selected, entries.indices.contains(i) else { return }
        selected = i
        selectionChanged()
    }

    // MARK: Session lifecycle

    @discardableResult
    func begin(trigger: Trigger, reverse: Bool) -> Bool {
        let s = settings
        let screen = Screens.target(for: s.showOnScreen)
        var wins = WindowProvider.windows(for: trigger, settings: s, display: Screens.displayID(of: screen))
        guard !wins.isEmpty else { return false }

        self.trigger = trigger
        missionMode = (trigger.styleOverride ?? s.style) == .missionControl
        if missionMode { wins = Self.groupedByApp(wins) }
        all = wins
        entries = wins
        recomputeGroups()
        spaceCount = PrivateAPI.spaceInfo().count

        let n = wins.count
        if missionMode && groupRanges.count > 1 {
            // Like ⌘Tab: land on the most recent window of the next (or last) app.
            expanded = false
            selected = groupRanges[reverse ? groupRanges.count - 1 : 1].lowerBound
        } else {
            expanded = missionMode && n > 1
            selected = n > 1 ? (reverse ? n - 1 : 1) : 0
        }

        active = true
        released = false
        searching = false
        query = ""
        shown = false

        let work = DispatchWorkItem { [weak self] in self?.present() }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(s.displayDelayMs), execute: work)
        return true
    }

    /// Stable grouping: apps in order of their first window, windows keep their relative order.
    private static func groupedByApp(_ wins: [Win]) -> [Win] {
        var order: [pid_t] = []
        var buckets: [pid_t: [Win]] = [:]
        for w in wins {
            if buckets[w.pid] == nil { order.append(w.pid) }
            buckets[w.pid, default: []].append(w)
        }
        return order.flatMap { buckets[$0] ?? [] }
    }

    private func recomputeGroups() {
        groupRanges = []
        var start = 0
        for i in 1...max(entries.count, 1) {
            if i == entries.count || entries[i].pid != entries[start].pid {
                if !entries.isEmpty { groupRanges.append(start..<i) }
                start = i
            }
        }
    }

    private func groupIndex(of i: Int) -> Int { groupRanges.firstIndex { $0.contains(i) } ?? 0 }

    private func present() {
        guard active, !shown else { return }
        shown = true
        render()
        loadThumbnails()
        updatePreview()
    }

    private func presentNow() {
        showWork?.cancel()
        present()
    }

    private func render() {
        let s = settings
        let screen = Screens.target(for: s.showOnScreen)
        if missionMode {
            if panel.isVisible { panel.hide(animated: false) }
            mission.show(entries: entries, ranges: groupRanges, expanded: expanded, selected: selected,
                         config: .init(settings: s, screen: screen), search: searching ? query : nil)
            return
        }
        let cfg = SwitcherPanel.Config(
            settings: s,
            style: trigger.styleOverride ?? s.style,
            size: trigger.sizeOverride ?? s.size,
            theme: trigger.themeOverride ?? s.theme,
            screen: screen,
            spaceCount: spaceCount)
        panel.show(entries: entries, selected: selected, config: cfg, search: searching ? query : nil)
    }

    /// Called when the hold modifier(s) are let go.
    func release() {
        guard active, !released else { return }
        released = true
        switch trigger.shortcutStyle {
        case .focusOnRelease:
            commit()
        case .doNothingOnRelease:
            presentNow()
        case .searchOnRelease:
            presentNow()
            beginSearch()
        }
    }

    func commit() {
        guard active else { return }
        let entry = entries.indices.contains(selected) ? entries[selected] : nil
        let follow = settings.cursorFollow
        end()
        if let entry { WindowActions.focus(entry, cursorFollow: follow) }
    }

    func cancel() { end() }

    /// Esc: leave an expanded app first, otherwise close the switcher.
    func escape() {
        if missionMode && expanded && groupRanges.count > 1 && !searching {
            expanded = false
            refresh()
        } else {
            cancel()
        }
    }

    private func end() {
        active = false
        released = false
        searching = false
        shown = false
        showWork?.cancel()
        thumbTask?.cancel()
        panel.hide(animated: settings.fadeOut)
        mission.hide(animated: settings.fadeOut)
        preview.hide()
    }

    // MARK: Navigation

    private func wrap(_ value: Int, _ count: Int) -> Int { ((value % count) + count) % count }

    func step(_ delta: Int) {
        guard active, !entries.isEmpty else { return }
        if missionMode {
            let g = groupIndex(of: selected)
            if expanded {
                let r = groupRanges[g]
                selected = r.lowerBound + wrap(selected - r.lowerBound + delta, r.count)
            } else {
                selected = groupRanges[wrap(g + delta, groupRanges.count)].lowerBound
            }
        } else {
            selected = wrap(selected + delta, entries.count)
        }
        selectionChanged()
    }

    func stepRow(_ dir: Int) {
        guard active, !entries.isEmpty else { return }
        if missionMode {
            let cols = mission.columns
            let g = groupIndex(of: selected)
            if expanded {
                let r = groupRanges[g]
                let target = selected + dir * cols
                if r.contains(target) { selected = target }
            } else {
                let target = g + dir * cols
                if groupRanges.indices.contains(target) { selected = groupRanges[target].lowerBound }
            }
        } else {
            let target = selected + dir * panel.columns
            if entries.indices.contains(target) { selected = target }
        }
        selectionChanged()
    }

    /// Mission Control: cycle through the windows of the selected app without leaving the overview.
    func stepInGroup(_ delta: Int) {
        guard active, missionMode, !entries.isEmpty else { return }
        let r = groupRanges[groupIndex(of: selected)]
        selected = r.lowerBound + wrap(selected - r.lowerBound + delta, r.count)
        selectionChanged()
    }

    /// Mouse wheel over an app's tile: select that app (if needed) and move through its windows.
    private func scrollOver(_ flat: Int, _ dir: Int) {
        guard active, missionMode, entries.indices.contains(flat) else { return }
        if expanded { step(dir); return }
        let g = groupIndex(of: flat)
        if groupIndex(of: selected) != g { selected = groupRanges[g].lowerBound }
        stepInGroup(dir)
        mission.zoom(flatIndex: selected)
    }

    /// Mission Control: show the selected app's windows as individual tiles (and back).
    func toggleExpand() {
        guard active, missionMode, !searching, groupRanges.count > 1 else { return }
        expanded.toggle()
        refresh()
    }

    private func selectionChanged() {
        guard shown else { return }
        if missionMode { return mission.select(selected) }
        panel.select(selected)
        updatePreview()
    }

    private func updatePreview() {
        guard shown, !missionMode, settings.previewSelectedWindow, entries.indices.contains(selected) else {
            return preview.hide()
        }
        preview.show(entries[selected], fade: settings.previewFadeIn)
    }

    // MARK: Search

    func beginSearch() {
        guard active else { return }
        searching = true
        query = ""
        applyFilter()
    }

    func typeSearch(_ text: String) { query += text; applyFilter() }

    func backspaceSearch() {
        guard !query.isEmpty else { return }
        query.removeLast()
        applyFilter()
    }

    private func applyFilter() {
        let words = query.lowercased().split(separator: " ").map(String.init)
        entries = words.isEmpty ? all : all.filter { w in
            let hay = "\(w.appName) \(w.title)".lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        recomputeGroups()
        expanded = missionMode && groupRanges.count == 1 && entries.count > 1
        selected = 0
        if shown { render() } else { presentNow() }
    }

    // MARK: Per-window actions

    func closeSelected() { if entries.indices.contains(selected) { close(entries[selected]) } }
    func minimizeSelected() { if entries.indices.contains(selected) { minimize(entries[selected]) } }
    func fullscreenSelected() { if entries.indices.contains(selected) { fullscreen(entries[selected]) } }

    func quitSelectedApp() {
        guard entries.indices.contains(selected) else { return }
        let w = entries[selected]
        WindowActions.quit(w)
        remove { $0.pid == w.pid }
    }

    func hideSelectedApp() {
        guard entries.indices.contains(selected) else { return }
        let w = entries[selected]
        WindowActions.toggleHidden(w)
        let hidden = !w.app.isHidden
        for other in all where other.pid == w.pid { other.isHidden = hidden }
        refresh()
    }

    private func close(_ w: Win) {
        if w.isWindowless { WindowActions.quit(w) } else { WindowActions.close(w) }
        remove { $0 === w }
    }

    private func minimize(_ w: Win) {
        if let state = WindowActions.toggleMinimized(w) { w.isMinimized = state; refresh() }
    }

    private func fullscreen(_ w: Win) {
        if let state = WindowActions.toggleFullscreen(w) { w.isFullscreen = state; refresh() }
    }

    private func remove(where predicate: (Win) -> Bool) {
        let current = entries.indices.contains(selected) ? entries[selected] : nil
        all.removeAll(where: predicate)
        entries.removeAll(where: predicate)
        if entries.isEmpty && all.isEmpty { return end() }
        recomputeGroups()
        if missionMode && groupRanges.count <= 1 { expanded = entries.count > 1 }
        selected = current.flatMap { c in entries.firstIndex { $0 === c } } ?? min(selected, max(entries.count - 1, 0))
        refresh()
    }

    private func refresh() {
        guard shown else { return }
        render()
        updatePreview()
    }

    // MARK: Thumbnails

    private func loadThumbnails() {
        guard missionMode || (trigger.styleOverride ?? settings.style) == .thumbnails else { return }
        thumbTask?.cancel()
        let ids = all.filter { !$0.isWindowless && !$0.isMinimized }.map(\.id)
        let size = missionMode ? CGSize(width: 1600, height: 1000) : CGSize(width: 520, height: 340)
        thumbTask = ThumbnailCache.shared.capture(ids, maxPixels: size) { [weak self] id, image in
            guard let self, self.active else { return }
            for w in self.all where w.id == id { w.thumbnail = image }
            self.panel.setThumbnail(windowID: id, image: image)
            self.mission.setThumbnail(windowID: id, image: image)
        }
    }
}
