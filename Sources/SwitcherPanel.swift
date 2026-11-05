import AppKit

// MARK: - Metrics

struct CellMetrics {
    let width: CGFloat
    let height: CGFloat
    let icon: CGFloat        // big icon (appIcons style / thumbnail placeholder / list icon)
    let font: CGFloat

    static func make(style: AppearanceStyle, size: AppearanceSize) -> CellMetrics {
        let i = [AppearanceSize.small: 0, .medium: 1, .large: 2, .auto: 1][size]!
        switch style {
        case .thumbnails, .missionControl:
            return [CellMetrics(width: 150, height: 128, icon: 48, font: 11),
                    CellMetrics(width: 200, height: 168, icon: 64, font: 12),
                    CellMetrics(width: 270, height: 220, icon: 84, font: 13)][i]
        case .appIcons:
            return [CellMetrics(width: 96, height: 104, icon: 56, font: 11),
                    CellMetrics(width: 124, height: 132, icon: 76, font: 12),
                    CellMetrics(width: 160, height: 164, icon: 104, font: 13)][i]
        case .titles:
            return [CellMetrics(width: 520, height: 34, icon: 22, font: 12),
                    CellMetrics(width: 640, height: 42, icon: 28, font: 13),
                    CellMetrics(width: 760, height: 52, icon: 36, font: 15)][i]
        }
    }
}

// MARK: - Small controls

private final class LightButton: NSView {
    let color: NSColor
    var action: (() -> Void)?
    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 13, height: 13))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        NSColor.black.withAlphaComponent(0.2).setStroke()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { action?() }
}

// MARK: - Cell

final class CellView: NSView {
    let win: Win
    private let metrics: CellMetrics
    private let style: AppearanceStyle
    private let thumb = NSImageView()
    private var lights: [LightButton] = []
    private let showLights: Bool
    private var trackingArea: NSTrackingArea?

    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onFullscreen: (() -> Void)?

    var isSelected = false { didSet { updateColors() } }

    init(win: Win, style: AppearanceStyle, metrics m: CellMetrics, settings: Settings, spaceCount: Int) {
        self.win = win
        self.metrics = m
        self.style = style
        showLights = !settings.hideTrafficLights && !win.isWindowless && style != .titles
        super.init(frame: NSRect(x: 0, y: 0, width: m.width, height: m.height))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 2
        build(settings: settings, spaceCount: spaceCount)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func label(_ text: String, size: CGFloat, mode: NSLineBreakMode, align: NSTextAlignment = .left) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size)
        l.textColor = .labelColor
        l.lineBreakMode = mode
        l.alignment = align
        return l
    }

    private func build(settings: Settings, spaceCount: Int) {
        let m = metrics
        let title = win.displayTitle(settings.showTitles)
        var rightEdge = m.width - 10   // badges grow leftwards from here

        func addBadge(symbol: String, tint: NSColor, help: String) {
            let size: CGFloat = style == .titles ? 18 : 16
            let iv = NSImageView(frame: NSRect(x: rightEdge - size,
                                               y: style == .titles ? (m.height - size) / 2 : m.height - size - 8,
                                               width: size, height: size))
            iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
            iv.symbolConfiguration = .init(pointSize: size - 2, weight: .semibold)
            iv.contentTintColor = tint
            iv.toolTip = help
            addSubview(iv)
            rightEdge -= size + 4
        }

        if !settings.hideStatusIcons {
            if win.isFullscreen { addBadge(symbol: "arrow.up.left.and.arrow.down.right.circle.fill", tint: .systemGreen, help: "Fullscreen") }
            if win.isMinimized { addBadge(symbol: "minus.circle.fill", tint: .systemYellow, help: "Minimized") }
            if win.isHidden { addBadge(symbol: "eye.slash.circle.fill", tint: .systemGray, help: "Hidden") }
        }
        if win.isWindowless {
            addBadge(symbol: "rectangle.dashed", tint: .secondaryLabelColor, help: "No open window")
        }
        if !settings.hideSpaceLabels, spaceCount > 1, let n = win.spaceNumber {
            let l = label("\(n)", size: 10, mode: .byClipping, align: .center)
            l.wantsLayer = true
            l.layer?.cornerRadius = 8
            l.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor
            let y = style == .titles ? (m.height - 16) / 2 : m.height - 24
            l.frame = NSRect(x: rightEdge - 18, y: y, width: 18, height: 16)
            addSubview(l)
            rightEdge -= 22
        }

        switch style {
        case .thumbnails:
            let small = max(16, m.icon / 3.2)
            let footer = small + 14
            thumb.frame = NSRect(x: 8, y: footer, width: m.width - 16, height: m.height - footer - 8)
            thumb.imageScaling = .scaleProportionallyUpOrDown
            addSubview(thumb)
            setThumbnail(win.thumbnail)

            let icon = NSImageView(frame: NSRect(x: 10, y: (footer - small) / 2, width: small, height: small))
            icon.image = win.icon
            addSubview(icon)
            let l = label(title, size: m.font, mode: settings.truncation.mode)
            l.frame = NSRect(x: 10 + small + 6, y: (footer - 17) / 2, width: m.width - small - 26, height: 17)
            addSubview(l)

        case .appIcons:
            let icon = NSImageView(frame: NSRect(x: (m.width - m.icon) / 2, y: m.height - m.icon - 14, width: m.icon, height: m.icon))
            icon.image = win.icon
            icon.alphaValue = win.isWindowless ? 0.6 : 1
            addSubview(icon)
            let l = label(title, size: m.font, mode: settings.truncation.mode, align: .center)
            l.frame = NSRect(x: 6, y: 12, width: m.width - 12, height: 17)
            addSubview(l)

        case .titles, .missionControl:
            let icon = NSImageView(frame: NSRect(x: 12, y: (m.height - m.icon) / 2, width: m.icon, height: m.icon))
            icon.image = win.icon
            addSubview(icon)
            let l = label(title, size: m.font, mode: settings.truncation.mode)
            let x = 12 + m.icon + 10
            l.frame = NSRect(x: x, y: (m.height - 18) / 2, width: max(40, rightEdge - x - 4), height: 18)
            addSubview(l)
        }

        if showLights {
            let defs: [(NSColor, () -> Void)] = [
                (.systemRed, { [weak self] in self?.onClose?() }),
                (.systemYellow, { [weak self] in self?.onMinimize?() }),
                (.systemGreen, { [weak self] in self?.onFullscreen?() }),
            ]
            for (i, d) in defs.enumerated() {
                let b = LightButton(color: d.0)
                b.action = d.1
                b.frame.origin = NSPoint(x: 12 + CGFloat(i) * 18, y: m.height - 25)
                b.isHidden = true
                addSubview(b)
                lights.append(b)
            }
        }
    }

    func setThumbnail(_ image: NSImage?) {
        guard style == .thumbnails else { return }
        if let image {
            thumb.image = image
            thumb.alphaValue = 1
        } else {
            thumb.image = win.icon
            thumb.alphaValue = 0.55
        }
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
            layer?.borderColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.45).cgColor : NSColor.clear.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() { updateColors() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { lights.forEach { $0.isHidden = false } }
    override func mouseExited(with event: NSEvent) { lights.forEach { $0.isHidden = true } }
    override func mouseMoved(with event: NSEvent) { onHover?() }
}

// MARK: - Panel

final class SwitcherPanel: NSPanel {
    struct Config {
        var settings: Settings
        var style: AppearanceStyle
        var size: AppearanceSize
        var theme: AppearanceTheme
        var screen: NSScreen
        var spaceCount: Int
    }

    private static let pad: CGFloat = 16
    private(set) var columns = 1
    private var cells: [CellView] = []
    private let scroll = NSScrollView()
    private let doc = NSView()
    private let searchLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No matching windows")

    var onClick: ((Win) -> Void)?
    var onHover: ((Int) -> Void)?
    var onClose: ((Win) -> Void)?
    var onMinimize: ((Win) -> Void)?
    var onFullscreen: ((Win) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = doc
        searchLabel.font = .systemFont(ofSize: 18, weight: .medium)
        searchLabel.lineBreakMode = .byTruncatingHead
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Picks the largest size at which every window fits on screen without scrolling.
    static func resolveSize(_ size: AppearanceSize, style: AppearanceStyle, count: Int, screen: NSScreen) -> AppearanceSize {
        guard size == .auto else { return size }
        let maxW = screen.frame.width * 0.9 - 2 * pad
        let maxH = screen.visibleFrame.height * 0.8 - 2 * pad
        for candidate in [AppearanceSize.large, .medium, .small] {
            let m = CellMetrics.make(style: style, size: candidate)
            let cols = style == .titles ? 1 : max(1, min(count, Int(maxW / m.width)))
            let rows = (count + cols - 1) / cols
            if CGFloat(rows) * m.height <= maxH { return candidate }
        }
        return .small
    }

    func show(entries: [Win], selected: Int, config: Config, search: String?) {
        let pad = Self.pad
        let screen = config.screen
        let size = Self.resolveSize(config.size, style: config.style, count: entries.count, screen: screen)
        let m = CellMetrics.make(style: config.style, size: size)

        appearance = config.theme == .system ? nil
            : NSAppearance(named: config.theme == .dark ? .darkAqua : .aqua)

        let maxW = screen.frame.width * 0.9
        let maxCols = max(1, Int((maxW - 2 * pad) / m.width))
        columns = config.style == .titles ? 1 : max(1, min(max(entries.count, 1), maxCols))
        let rows = max(1, (entries.count + columns - 1) / columns)
        let contentW = CGFloat(columns) * m.width
        let contentH = CGFloat(rows) * m.height
        let searchH: CGFloat = search != nil ? 44 : 0
        let maxH = screen.visibleFrame.height * 0.85
        let panelW = max(contentW + 2 * pad, search != nil ? 360 : 0)
        let panelH = min(contentH + 2 * pad + searchH, maxH)

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true

        scroll.frame = NSRect(x: 0, y: pad / 2, width: panelW, height: panelH - searchH - pad)
        doc.frame = NSRect(x: 0, y: 0, width: panelW, height: contentH)
        doc.subviews.forEach { $0.removeFromSuperview() }

        let xInset = (panelW - contentW) / 2
        cells = entries.enumerated().map { i, w in
            let c = CellView(win: w, style: config.style, metrics: m, settings: config.settings, spaceCount: config.spaceCount)
            let r = i / columns, col = i % columns
            c.frame.origin = NSPoint(x: xInset + CGFloat(col) * m.width, y: contentH - CGFloat(r + 1) * m.height)
            c.onClick = { [weak self] in self?.onClick?(w) }
            c.onHover = { [weak self] in self?.onHover?(i) }
            c.onClose = { [weak self] in self?.onClose?(w) }
            c.onMinimize = { [weak self] in self?.onMinimize?(w) }
            c.onFullscreen = { [weak self] in self?.onFullscreen?(w) }
            doc.addSubview(c)
            return c
        }
        effect.addSubview(scroll)

        if let search {
            searchLabel.stringValue = search.isEmpty ? "Type to search…" : search
            searchLabel.textColor = search.isEmpty ? .secondaryLabelColor : .labelColor
            searchLabel.frame = NSRect(x: pad + 8, y: panelH - searchH + 4, width: panelW - 2 * pad - 16, height: 26)
            effect.addSubview(searchLabel)
            let line = NSBox(frame: NSRect(x: pad, y: panelH - searchH - 2, width: panelW - 2 * pad, height: 1))
            line.boxType = .separator
            effect.addSubview(line)
        }
        if entries.isEmpty {
            emptyLabel.sizeToFit()
            emptyLabel.frame.origin = NSPoint(x: (panelW - emptyLabel.frame.width) / 2, y: (panelH - searchH) / 2)
            effect.addSubview(emptyLabel)
        }

        contentView = effect
        setFrame(NSRect(x: screen.frame.midX - panelW / 2, y: screen.frame.midY - panelH / 2,
                        width: panelW, height: panelH), display: true)
        doc.scroll(NSPoint(x: 0, y: contentH))
        select(selected)
        if !isVisible { alphaValue = 1 }
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (i, c) in cells.enumerated() { c.isSelected = (i == index) }
        if cells.indices.contains(index) { doc.scrollToVisible(cells[index].frame.insetBy(dx: 0, dy: -8)) }
    }

    func setThumbnail(windowID: CGWindowID, image: NSImage) {
        for c in cells where c.win.id == windowID { c.setThumbnail(image) }
    }

    func hide(animated: Bool) {
        func finish() {
            orderOut(nil)
            contentView = nil
            cells = []
            alphaValue = 1
        }
        guard animated, isVisible else { return finish() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: finish)
    }
}

// MARK: - Live preview of the selected window

final class PreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private var task: Task<Void, Never>?
    private var currentID: CGWindowID = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        imageView.imageScaling = .scaleAxesIndependently
        contentView = imageView
    }

    override var canBecomeKey: Bool { false }

    func show(_ w: Win, fade: Bool) {
        guard !w.isWindowless, !w.isMinimized, w.onVisibleSpace, !w.bounds.isEmpty else { return hide() }
        guard w.id != currentID else { return }
        currentID = w.id
        task?.cancel()
        let primaryH = NSScreen.screens[0].frame.height
        let frame = NSRect(x: w.bounds.minX, y: primaryH - w.bounds.maxY, width: w.bounds.width, height: w.bounds.height)
        let id = w.id
        task = Task { [weak self] in
            guard let image = await ThumbnailCache.captureFull(id), !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentID == id else { return }
                self.imageView.image = image
                self.setFrame(frame, display: true)
                if fade && !self.isVisible {
                    self.alphaValue = 0
                    self.orderFrontRegardless()
                    NSAnimationContext.runAnimationGroup { $0.duration = 0.15; self.animator().alphaValue = 1 }
                } else {
                    self.alphaValue = 1
                    self.orderFrontRegardless()
                }
            }
        }
    }

    func hide() {
        task?.cancel()
        currentID = 0
        orderOut(nil)
        imageView.image = nil
    }
}
