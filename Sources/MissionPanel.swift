import AppKit

// MARK: - One window thumbnail inside a tile

private final class ThumbView: NSView {
    let win: Win
    private let imageView = NSImageView()
    var image: NSImage? { didSet { refresh() } }
    var isSelected = false { didSet { updateBorder() } }

    init(win: Win) {
        self.win = win
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        imageView.imageScaling = .scaleAxesIndependently
        addSubview(imageView)
        image = win.thumbnail
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if image != nil {
            imageView.frame = bounds
        } else {
            let s = min(bounds.width, bounds.height) * 0.5
            imageView.frame = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        }
    }

    private func refresh() {
        if let image {
            imageView.image = image
            imageView.imageScaling = .scaleAxesIndependently
            layer?.backgroundColor = NSColor.black.cgColor
        } else {
            imageView.image = win.icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        }
        needsLayout = true
    }

    private func updateBorder() {
        layer?.borderWidth = isSelected ? 3 : 1
        layer?.borderColor = (isSelected ? NSColor.white : NSColor.white.withAlphaComponent(0.25)).cgColor
    }

    /// Width / height of what will be drawn.
    var aspect: CGFloat {
        if let image, image.size.height > 0 { return image.size.width / image.size.height }
        if win.bounds.height > 0 { return win.bounds.width / win.bounds.height }
        return 1.6
    }
}

// MARK: - A tile: a stack of windows of one app (or a single window when expanded)

private final class MissionTile: NSView {
    let wins: [Win]
    private let single: Bool
    private var thumbs: [ThumbView] = []     // index 0 = front-most
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let iconSize: CGFloat
    private var region: NSRect = .zero
    private let maxStack = 4

    var onClick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var scrollAccumulator: CGFloat = 0
    private var bigIcon: NSImageView?
    var isZoomed = false { didSet { applyBackground() } }

    private(set) var innerSelected = 0
    private(set) var isSelected = false

    static func iconSize(single: Bool) -> CGFloat { single ? 38 : 68 }
    static func labelHeight(single: Bool) -> CGFloat { iconSize(single: single) / 2 + 46 }

    init(wins: [Win], single: Bool, size: NSSize) {
        self.wins = wins
        self.single = single
        iconSize = Self.iconSize(single: single)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 16

        let labelH = Self.labelHeight(single: single)
        region = NSRect(x: 12, y: labelH, width: size.width - 24, height: size.height - labelH - 12)

        if wins.count == 1 && wins[0].isWindowless {
            let iv = NSImageView(frame: NSRect(x: region.midX - region.height * 0.3, y: region.midY - region.height * 0.3,
                                               width: region.height * 0.6, height: region.height * 0.6))
            iv.image = wins[0].icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.alphaValue = 0.7
            bigIcon = iv
            addSubview(iv)
        } else {
            thumbs = wins.prefix(maxStack).map { ThumbView(win: $0) }
            for t in thumbs.reversed() { addSubview(t) }   // back first
            layoutThumbs()
        }

        iconView.frame = NSRect(x: (size.width - iconSize) / 2, y: labelH - iconSize / 2, width: iconSize, height: iconSize)
        iconView.image = wins[0].icon
        addSubview(iconView)

        for (l, size, weight) in [(titleLabel, single ? 12 : 15, NSFont.Weight.medium), (subLabel, 12, .regular)] as [(NSTextField, CGFloat, NSFont.Weight)] {
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = .white
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            l.shadow = shadow
            addSubview(l)
        }
        let titleY = labelH - iconSize / 2 - 22
        titleLabel.frame = NSRect(x: 8, y: titleY, width: size.width - 16, height: 20)
        subLabel.frame = NSRect(x: 8, y: titleY - 17, width: size.width - 16, height: 16)
        subLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        refreshLabels()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Cascade: back windows peek out up and to the left, the front one sits bottom-right.
    private func layoutThumbs() {
        let k = thumbs.count
        guard k > 0 else { return }
        let d: CGFloat = k > 1 ? min(30, region.width * 0.1) : 0
        let slotW = region.width - CGFloat(k - 1) * d
        let slotH = region.height - CGFloat(k - 1) * d
        for (j, t) in thumbs.enumerated() {
            if isSelected && j == innerSelected && k > 1 {
                // The chosen window pops out to the full size of the tile, above the rest of the stack.
                var w = region.width, h = w / t.aspect
                if h > region.height { h = region.height; w = h * t.aspect }
                t.frame = NSRect(x: region.midX - w / 2, y: region.midY - h / 2, width: w, height: h).integral
                continue
            }
            var w = slotW, h = w / t.aspect
            if h > slotH { h = slotH; w = h * t.aspect }
            let back = CGFloat(k - 1 - j)
            let slotX = region.minX + back * d
            let slotY = region.maxY - slotH - back * d
            t.frame = NSRect(x: slotX + (slotW - w) / 2, y: slotY + (slotH - h) / 2, width: w, height: h).integral
        }
        // Back-to-front stacking, with the selected window last (on top), below the icon and labels.
        let order = thumbs.indices.reversed().filter { !(isSelected && $0 == innerSelected) }
            + (isSelected && innerSelected < k ? [innerSelected] : [])
        for j in order {
            thumbs[j].removeFromSuperview()
            addSubview(thumbs[j], positioned: .below, relativeTo: iconView)
        }
    }

    func setThumbnail(windowID: CGWindowID, image: NSImage) {
        for t in thumbs where t.win.id == windowID { t.image = image }
        layoutThumbs()
    }

    func setSelection(selected: Bool, inner: Int) {
        isSelected = selected
        innerSelected = inner
        for (j, t) in thumbs.enumerated() { t.isSelected = selected && j == inner }
        layoutThumbs()
        applyBackground()
        refreshLabels()
    }

    private func applyBackground() {
        if isZoomed {
            layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        } else {
            layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
            layer?.borderWidth = isSelected ? 2 : 0
            layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        }
    }

    /// Re-lays out the content for a new tile size (used when a group is zoomedTile).
    func resize(to size: NSSize) {
        setFrameSize(size)
        let labelH = Self.labelHeight(single: single)
        region = NSRect(x: 12, y: labelH, width: size.width - 24, height: size.height - labelH - 12)
        if let iv = bigIcon {
            iv.frame = NSRect(x: region.midX - region.height * 0.3, y: region.midY - region.height * 0.3,
                              width: region.height * 0.6, height: region.height * 0.6)
        }
        iconView.frame = NSRect(x: (size.width - iconSize) / 2, y: labelH - iconSize / 2, width: iconSize, height: iconSize)
        let titleY = labelH - iconSize / 2 - 22
        titleLabel.frame = NSRect(x: 8, y: titleY, width: size.width - 16, height: 20)
        subLabel.frame = NSRect(x: 8, y: titleY - 17, width: size.width - 16, height: 16)
        layoutThumbs()
    }

    private func refreshLabels() {
        if single {
            titleLabel.stringValue = wins[0].displayTitle(.windowTitle)
            subLabel.stringValue = ""
            return
        }
        titleLabel.stringValue = wins[0].appName
        if wins.count > 1 {
            let i = min(innerSelected, wins.count - 1)
            let title = wins[i].title.isEmpty ? "Untitled" : wins[i].title
            subLabel.stringValue = isSelected ? "\(i + 1)/\(wins.count) · \(title)" : "\(wins.count) windows"
        } else {
            subLabel.stringValue = wins[0].isWindowless ? "No windows" : ""
        }
    }

    /// Index of the window under a point in tile coordinates (front-most first), if any.
    private func windowIndex(at p: NSPoint) -> Int? {
        if isSelected, thumbs.indices.contains(innerSelected), thumbs[innerSelected].frame.contains(p) { return innerSelected }
        return thumbs.firstIndex { $0.frame.contains(p) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard wins.count > 1 else { return }
        let precise = event.hasPreciseScrollingDeltas
        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = precise ? 14 : 1
        while abs(scrollAccumulator) >= threshold {
            onScroll?(scrollAccumulator < 0 ? 1 : -1)
            scrollAccumulator -= scrollAccumulator < 0 ? -threshold : threshold
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onClick?(windowIndex(at: p) ?? innerSelected)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onHover?(windowIndex(at: p) ?? (isSelected ? innerSelected : 0))
    }

    override func mouseExited(with event: NSEvent) { onExit?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
}

// MARK: - Panel

/// Full-screen, Mission-Control-like presentation: one tile per app with its windows cascaded,
/// or (expanded) one tile per window of the selected app.
final class MissionPanel: NSPanel {
    struct Config {
        var settings: Settings
        var screen: NSScreen
    }

    private var tiles: [MissionTile] = []
    private var tileRanges: [Range<Int>] = []
    private var tileFrames: [NSRect] = []
    private var zoomedTile: Int?
    private var zoomFactor: CGFloat = 1.6
    private(set) var columns = 1
    private let searchLabel = NSTextField(labelWithString: "")

    var onClick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    /// Mouse wheel over a tile: (first flat index of that tile, direction).
    var onScroll: ((Int, Int) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        searchLabel.font = .systemFont(ofSize: 22, weight: .medium)
        searchLabel.textColor = .white
        searchLabel.alignment = .center
        searchLabel.wantsLayer = true
        searchLabel.layer?.cornerRadius = 12
        searchLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(entries: [Win], ranges: [Range<Int>], expanded: Bool, selected: Int, config: Config, search: String?) {
        let screen = config.screen
        let bounds = NSRect(origin: .zero, size: screen.frame.size)

        // Which windows each tile represents, as flat ranges into `entries`.
        if expanded, let g = ranges.first(where: { $0.contains(selected) }) {
            tileRanges = g.map { $0..<($0 + 1) }
        } else {
            tileRanges = ranges
        }
        let single = expanded
        let n = max(tileRanges.count, 1)

        let content = NSView(frame: bounds)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor

        // Pick the column count that gives the biggest thumbnails.
        let gap: CGFloat = 28
        let top: CGFloat = search != nil ? 130 : 90
        let area = NSSize(width: bounds.width - 160, height: bounds.height - top - 60)
        let labelH = MissionTile.labelHeight(single: single)
        var best: (cols: Int, scale: CGFloat) = (1, 0)
        for cols in 1...n {
            let rows = (n + cols - 1) / cols
            let cellW = (area.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let s = min((cellW - 24) / 16, (cellH - labelH - 12) / 10)
            if s > best.scale { best = (cols, s) }
        }
        let scale = max(6, min(best.scale, 44))
        columns = best.cols
        let rows = (n + columns - 1) / columns
        let tileW = 16 * scale + 24
        let tileH = 10 * scale + labelH + 12
        let gridH = CGFloat(rows) * tileH + CGFloat(rows - 1) * gap
        let originY = bounds.height - top - (area.height - gridH) / 2   // top edge of grid

        tiles = tileRanges.enumerated().map { i, r in
            let wins = Array(entries[r])
            let tile = MissionTile(wins: wins, single: single, size: NSSize(width: tileW, height: tileH))
            let row = i / columns, col = i % columns
            let inRow = row == rows - 1 ? n - columns * (rows - 1) : columns
            let rowW = CGFloat(inRow) * tileW + CGFloat(inRow - 1) * gap
            tile.frame.origin = NSPoint(x: (bounds.width - rowW) / 2 + CGFloat(col) * (tileW + gap),
                                        y: originY - CGFloat(row + 1) * tileH - CGFloat(row) * gap)
            tile.onClick = { [weak self] inner in self?.onClick?(r.lowerBound + inner) }
            tile.onHover = { [weak self] inner in self?.onHover?(r.lowerBound + inner) }
            tile.onScroll = { [weak self] dir in self?.onScroll?(r.lowerBound, dir) }
            tile.onExit = { [weak self] in if self?.zoomedTile == i { self?.setZoom(nil) } }
            content.addSubview(tile)
            return tile
        }

        if let search {
            searchLabel.stringValue = search.isEmpty ? "Type to search…" : search
            searchLabel.textColor = search.isEmpty ? NSColor.white.withAlphaComponent(0.6) : .white
            let w: CGFloat = min(520, bounds.width - 200)
            searchLabel.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height - 90, width: w, height: 38)
            content.addSubview(searchLabel)
        }
        if entries.isEmpty {
            let l = NSTextField(labelWithString: "No matching windows")
            l.font = .systemFont(ofSize: 18)
            l.textColor = NSColor.white.withAlphaComponent(0.7)
            l.sizeToFit()
            l.frame.origin = NSPoint(x: (bounds.width - l.frame.width) / 2, y: bounds.height / 2)
            content.addSubview(l)
        }

        contentView = content
        tileFrames = tiles.map(\.frame)
        zoomedTile = nil
        zoomFactor = CGFloat(config.settings.groupZoom)
        setFrame(screen.frame, display: true)
        select(selected)
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Grows the tile containing `flat` by the configured factor (no-op at 1×).
    func zoom(flatIndex flat: Int) {
        guard zoomFactor > 1.01, let i = tileRanges.firstIndex(where: { $0.contains(flat) }) else { return }
        setZoom(i)
    }

    private func setZoom(_ index: Int?) {
        guard index != zoomedTile else { return }
        if let old = zoomedTile, tiles.indices.contains(old) {
            tiles[old].isZoomed = false
            tiles[old].setFrameOrigin(tileFrames[old].origin)
            tiles[old].resize(to: tileFrames[old].size)
        }
        zoomedTile = index
        guard let i = index, tiles.indices.contains(i), let content = contentView else { return }
        let orig = tileFrames[i]
        let b = content.bounds
        let f = min(zoomFactor, (b.width - 40) / orig.width, (b.height - 40) / orig.height)
        let size = NSSize(width: orig.width * f, height: orig.height * f)
        var o = NSPoint(x: orig.midX - size.width / 2, y: orig.midY - size.height / 2)
        o.x = max(20, min(o.x, b.width - size.width - 20))
        o.y = max(20, min(o.y, b.height - size.height - 20))
        tiles[i].isZoomed = true
        tiles[i].setFrameOrigin(o)
        tiles[i].resize(to: size)
        content.addSubview(tiles[i], positioned: .above, relativeTo: nil)
    }

    func select(_ flat: Int) {
        if let z = zoomedTile, tileRanges.indices.contains(z), !tileRanges[z].contains(flat) { setZoom(nil) }
        for (i, t) in tiles.enumerated() {
            let r = tileRanges[i]
            t.setSelection(selected: r.contains(flat), inner: r.contains(flat) ? flat - r.lowerBound : 0)
        }
    }

    func setThumbnail(windowID: CGWindowID, image: NSImage) {
        tiles.forEach { $0.setThumbnail(windowID: windowID, image: image) }
    }

    func hide(animated: Bool) {
        func finish() {
            orderOut(nil)
            contentView = nil
            tiles = []
            tileRanges = []
            tileFrames = []
            zoomedTile = nil
            alphaValue = 1
        }
        guard animated, isVisible else { return finish() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: finish)
    }
}
