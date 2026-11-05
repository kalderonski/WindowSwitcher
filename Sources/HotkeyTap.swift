import AppKit

/// Global keyboard interception that drives the Switcher.
final class HotkeyTap {
    private let switcher: Switcher
    private var port: CFMachPort?
    private var swallowedKeyUps = Set<Int64>()

    init(switcher: Switcher) { self.switcher = switcher }

    var isInstalled: Bool { port != nil }

    @discardableResult
    func install() -> Bool {
        if port != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let p = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        port = p
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, p, 0), .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)
        return true
    }

    private func modifiers(_ event: CGEvent) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Shortcut.relevantMask)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let mods = modifiers(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            if switcher.active && !switcher.released && !switcher.trigger.hold.flags.isSubset(of: NSEvent.modifierFlags) {
                switcher.cancel()
            }
            return pass

        case .flagsChanged:
            if switcher.active && !switcher.released && !switcher.trigger.hold.flags.isSubset(of: mods) {
                switcher.release()
            }
            return pass

        case .keyDown:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            return keyDown(code, mods, event) ? nil : pass

        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowedKeyUps.remove(code) != nil ? nil : pass

        default:
            return pass
        }
    }

    /// Returns true when the key was consumed.
    private func keyDown(_ code: Int, _ mods: NSEvent.ModifierFlags, _ event: CGEvent) -> Bool {
        let s = SettingsStore.shared.s

        if !switcher.active {
            for t in s.triggers where t.next.hasKey && t.next.keyCode == code && !t.hold.flags.isEmpty {
                let required = t.hold.flags
                guard required.isSubset(of: mods), mods.subtracting(required).isSubset(of: .shift) else { continue }
                if isIgnoredForFrontApp(s) { return false }
                let reverse = s.previousKey.flags.contains(.shift) && !s.previousKey.hasKey
                    && mods.contains(.shift) && !required.contains(.shift)
                swallowedKeyUps.insert(Int64(code))
                switcher.begin(trigger: t, reverse: reverse)
                return true
            }
            return false
        }

        // Missed the modifier release (e.g. event tap was disabled): finish now.
        if !switcher.released && !switcher.trigger.hold.flags.isSubset(of: mods) {
            switcher.release()
            if !switcher.active { return false }
        }

        swallowedKeyUps.insert(Int64(code))
        let shift = mods.contains(.shift)
        let isNext = s.triggers.contains { $0.next.hasKey && $0.next.keyCode == code }
        let isReturn = code == 36 || code == 76

        if switcher.searching {
            switch code {
            case _ where isReturn || (s.focusKey.hasKey && code == s.focusKey.keyCode): switcher.commit()
            case _ where code == s.cancelKey.keyCode: switcher.cancel()
            case 51: switcher.backspaceSearch()
            case 123: switcher.step(-1)
            case 124: switcher.step(1)
            case 125: switcher.stepRow(1)
            case 126: switcher.stepRow(-1)
            case _ where isNext: switcher.step(shift ? -1 : 1)
            default:
                if !mods.contains(.command), !mods.contains(.control),
                   let chars = NSEvent(cgEvent: event)?.characters(byApplyingModifiers: []),
                   let first = chars.unicodeScalars.first, first.value >= 0x20, first.value != 0x7f,
                   !(0xF700...0xF8FF).contains(first.value) {
                    switcher.typeSearch(chars)
                }
            }
            return true
        }

        if switcher.isMission {
            if s.subSelectKey.hasKey && code == s.subSelectKey.keyCode { switcher.stepInGroup(shift ? -1 : 1); return true }
            if s.expandKey.hasKey && code == s.expandKey.keyCode { switcher.toggleExpand(); return true }
        }
        if isNext { switcher.step(shift ? -1 : 1); return true }
        if s.previousKey.hasKey && code == s.previousKey.keyCode { switcher.step(-1); return true }
        if s.focusKey.hasKey && code == s.focusKey.keyCode || isReturn { switcher.commit(); return true }

        let actions: [(Shortcut, () -> Void)] = [
            (s.cancelKey, { self.switcher.escape() }),
            (s.closeKey, { self.switcher.closeSelected() }),
            (s.minimizeKey, { self.switcher.minimizeSelected() }),
            (s.fullscreenKey, { self.switcher.fullscreenSelected() }),
            (s.quitKey, { self.switcher.quitSelectedApp() }),
            (s.hideKey, { self.switcher.hideSelectedApp() }),
            (s.searchKey, { self.switcher.beginSearch() }),
        ]
        for (shortcut, action) in actions where shortcut.hasKey && shortcut.keyCode == code {
            action()
            return true
        }

        if s.arrowKeys {
            switch code {
            case 123: switcher.step(-1); return true
            case 124: switcher.step(1); return true
            case 125: switcher.stepRow(1); return true
            case 126: switcher.stepRow(-1); return true
            default: break
            }
        }
        if s.vimKeys {
            switch code {
            case 4: switcher.step(-1)       // h
            case 37: switcher.step(1)       // l
            case 38: switcher.stepRow(1)    // j
            case 40: switcher.stepRow(-1)   // k
            default: break
            }
        }
        return true
    }

    private func isIgnoredForFrontApp(_ s: Settings) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              let ex = s.exceptions.first(where: { $0.bundleID == id }) else { return false }
        switch ex.ignore {
        case .none: return false
        case .always: return true
        case .whenFullscreen:
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, 0.1)
            var win: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &win) == .success, let win else { return false }
            var fs: CFTypeRef?
            AXUIElementCopyAttributeValue(win as! AXUIElement, "AXFullScreen" as CFString, &fs)
            return (fs as? Bool) ?? false
        }
    }
}
