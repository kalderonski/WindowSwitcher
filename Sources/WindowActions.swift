import AppKit
import ApplicationServices
import ScreenCaptureKit

enum WindowActions {
    static func axWindow(for w: Win) -> AXUIElement? {
        guard !w.isWindowless else { return nil }
        let app = AXUIElementCreateApplication(w.pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let wins = value as? [AXUIElement] else { return nil }
        for el in wins {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(el, &wid) == .success, wid == w.id { return el }
        }
        return nil
    }

    static func focus(_ w: Win, cursorFollow: CursorFollow) {
        if w.isWindowless {
            if w.app.isHidden { w.app.unhide() }
            if !w.app.activate(options: [.activateIgnoringOtherApps]), let url = w.app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        let ax = axWindow(for: w)
        if let ax, w.isMinimized { AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        if w.app.isHidden { w.app.unhide() }

        let focused = PrivateAPI.focus(pid: w.pid, window: w.id)
        if let ax {
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if !focused {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(w.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            w.app.activate(options: [.activateIgnoringOtherApps])
        }
        FocusTracker.shared.record(w.id)

        let moveCursor: Bool
        switch cursorFollow {
        case .never: moveCursor = false
        case .always: moveCursor = true
        case .differentScreen:
            var did = CGDirectDisplayID(); var n: UInt32 = 0
            CGGetDisplaysWithPoint(CGEvent(source: nil)?.location ?? .zero, 1, &did, &n)
            moveCursor = n == 0 || did != w.displayID
        }
        if moveCursor, !w.bounds.isEmpty {
            CGWarpMouseCursorPosition(CGPoint(x: w.bounds.midX, y: w.bounds.midY))
        }
    }

    static func close(_ w: Win) {
        if w.isWindowless { return }
        guard let ax = axWindow(for: w) else { return }
        var btn: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXCloseButtonAttribute as CFString, &btn) == .success, let btn {
            AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString)
        }
    }

    /// Returns the new minimized state when it could be toggled.
    @discardableResult
    static func toggleMinimized(_ w: Win) -> Bool? {
        guard let ax = axWindow(for: w) else { return nil }
        let target = !w.isMinimized
        AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, target ? kCFBooleanTrue : kCFBooleanFalse)
        return target
    }

    @discardableResult
    static func toggleFullscreen(_ w: Win) -> Bool? {
        guard let ax = axWindow(for: w) else { return nil }
        let target = !w.isFullscreen
        AXUIElementSetAttributeValue(ax, "AXFullScreen" as CFString, target ? kCFBooleanTrue : kCFBooleanFalse)
        return target
    }

    static func quit(_ w: Win) { w.app.terminate() }

    static func toggleHidden(_ w: Win) {
        if w.app.isHidden { w.app.unhide() } else { w.app.hide() }
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [CGWindowID: NSImage] = [:]

    func image(for id: CGWindowID) -> NSImage? { images[id] }

    static var canCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures thumbnails concurrently; `onEach` is called on the main actor as each one arrives.
    @discardableResult
    func capture(_ ids: [CGWindowID], maxPixels: CGSize = CGSize(width: 520, height: 340), onEach: @escaping @MainActor (CGWindowID, NSImage) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            guard Self.canCapture,
                  let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            else { return }
            let map = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                for id in ids {
                    guard let sc = map[id] else { continue }
                    group.addTask { (id, await Self.render(sc, maxPixels: maxPixels)) }
                }
                for await (id, image) in group {
                    guard !Task.isCancelled, let image else { continue }
                    await MainActor.run {
                        self?.images[id] = image
                        onEach(id, image)
                    }
                }
            }
        }
    }

    /// Full-size capture used for the live preview.
    static func captureFull(_ id: CGWindowID) async -> NSImage? {
        guard canCapture,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let sc = content.windows.first(where: { $0.windowID == id }) else { return nil }
        return await render(sc, maxPixels: CGSize(width: 3840, height: 2400))
    }

    private static func render(_ window: SCWindow, maxPixels: CGSize) async -> NSImage? {
        let cfg = SCStreamConfiguration()
        let scale = min(maxPixels.width / window.frame.width, maxPixels.height / window.frame.height, 2)
        cfg.width = max(1, Int(window.frame.width * scale))
        cfg.height = max(1, Int(window.frame.height * scale))
        cfg.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: window.frame.width, height: window.frame.height))
    }
}
