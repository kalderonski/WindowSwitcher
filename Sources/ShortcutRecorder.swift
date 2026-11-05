import AppKit
import SwiftUI

enum RecorderMode {
    case modifiersOnly   // hold keys, e.g. ⌥
    case keyOnly         // a single key, optional modifiers (⇧ alone is accepted too)
}

final class RecorderField: NSView {
    var mode: RecorderMode = .keyOnly
    var shortcut = Shortcut() { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }
    private var peak: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? "Type shortcut…" : shortcut.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                                withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
        peak = []
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    private func finish(_ s: Shortcut) {
        shortcut = s
        onChange?(s)
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let code = Int(event.keyCode)
        if code == 53 { recording = false; window?.makeFirstResponder(nil); return }   // Esc cancels
        if mode == .modifiersOnly { return }
        if code == 51 || code == 117 { finish(Shortcut()); return }                      // Delete clears
        finish(Shortcut(keyCode: code, modifiers: event.modifierFlags))
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return }
        let mods = event.modifierFlags.intersection(Shortcut.relevantMask)
        if !mods.isEmpty { peak.formUnion(mods) }
        // All modifiers released after pressing some: accept a modifier-only shortcut.
        if mods.isEmpty && !peak.isEmpty { finish(Shortcut(modifiers: peak)) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    var mode: RecorderMode = .keyOnly

    func makeNSView(context: Context) -> RecorderField {
        let f = RecorderField()
        f.mode = mode
        f.shortcut = shortcut
        f.onChange = { new in DispatchQueue.main.async { shortcut = new } }
        f.setContentHuggingPriority(.required, for: .horizontal)
        return f
    }

    func updateNSView(_ f: RecorderField, context: Context) {
        f.mode = mode
        f.shortcut = shortcut
        f.onChange = { new in DispatchQueue.main.async { shortcut = new } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecorderField, context: Context) -> CGSize? {
        CGSize(width: 150, height: 24)
    }
}
