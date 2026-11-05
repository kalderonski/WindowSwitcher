import AppKit

// Usage: make_icon <output.iconset dir>
func render(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 0.225, yRadius: s * 0.225)
    NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                        NSColor(red: 0.10, green: 0.55, blue: 0.98, alpha: 1)])!.draw(in: bg, angle: -60)

    func window(_ r: NSRect, alpha: CGFloat, selected: Bool) {
        let p = NSBezierPath(roundedRect: r, xRadius: s * 0.045, yRadius: s * 0.045)
        NSColor.white.withAlphaComponent(alpha).setFill()
        p.fill()
        // title bar dots
        let d = s * 0.022
        for i in 0..<3 {
            let dot = NSRect(x: r.minX + s * 0.04 + CGFloat(i) * d * 2.2, y: r.maxY - s * 0.06, width: d, height: d)
            (selected ? NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 0.9) : NSColor.black.withAlphaComponent(0.25)).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }
    let w = s * 0.40, h = s * 0.30
    window(NSRect(x: s * 0.18, y: s * 0.55, width: w, height: h), alpha: 0.45, selected: false)
    window(NSRect(x: s * 0.42, y: s * 0.40, width: w, height: h), alpha: 0.70, selected: false)
    // front, selected window with highlight ring
    let front = NSRect(x: s * 0.30, y: s * 0.20, width: w, height: h)
    let ring = NSBezierPath(roundedRect: front.insetBy(dx: -s * 0.02, dy: -s * 0.02), xRadius: s * 0.06, yRadius: s * 0.06)
    ring.lineWidth = s * 0.018
    NSColor.white.setStroke()
    ring.stroke()
    window(front, alpha: 1.0, selected: true)
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
