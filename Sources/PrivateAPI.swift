import AppKit

/// Private WindowServer / SkyLight entry points, resolved at runtime so a missing symbol degrades
/// gracefully instead of failing to launch.
enum PrivateAPI {
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym<T>(_ names: [String], as _: T.Type) -> T? {
        for n in names {
            if let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, n) {
                return unsafeBitCast(p, to: T.self)
            }
        }
        return nil
    }

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias WindowSpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SetFrontFn = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    private typealias PostEventFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32
    private typealias PSNFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias HotKeyEnabledFn = @convention(c) (Int32, Bool) -> Int32

    private static let mainConn = sym(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnFn.self)
    private static let displaySpaces = sym(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: DisplaySpacesFn.self)
    private static let windowSpaces = sym(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: WindowSpacesFn.self)
    private static let setFront = sym(["_SLPSSetFrontProcessWithOptions"], as: SetFrontFn.self)
    private static let postEvent = sym(["SLPSPostEventRecordTo"], as: PostEventFn.self)
    private static let processForPID = sym(["GetProcessForPID"], as: PSNFn.self)
    private static let hotKeyEnabled = sym(["CGSSetSymbolicHotKeyEnabled"], as: HotKeyEnabledFn.self)

    // MARK: Spaces

    struct SpaceInfo {
        var visible: Set<UInt64> = []
        var numbers: [UInt64: Int] = [:]
        var fullscreen: Set<UInt64> = []
        var count: Int { numbers.count }
    }

    static func spaceInfo() -> SpaceInfo {
        var info = SpaceInfo()
        guard let mainConn, let displaySpaces,
              let displays = displaySpaces(mainConn())?.takeRetainedValue() as? [[String: Any]] else { return info }
        var n = 0
        for display in displays {
            if let cur = display["Current Space"] as? [String: Any], let id = cur["id64"] as? Int {
                info.visible.insert(UInt64(id))
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = space["id64"] as? Int else { continue }
                if (space["type"] as? Int ?? 0) == 0 {
                    n += 1
                    info.numbers[UInt64(id)] = n
                } else {
                    info.fullscreen.insert(UInt64(id))
                }
            }
        }
        return info
    }

    static func spaces(of window: CGWindowID) -> [UInt64] {
        guard let mainConn, let windowSpaces,
              let arr = windowSpaces(mainConn(), 0x7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return arr.map { $0.uint64Value }
    }

    // MARK: Focusing

    /// Brings a specific window (possibly on another Space) to the front and makes it key.
    @discardableResult
    static func focus(pid: pid_t, window: CGWindowID) -> Bool {
        guard let setFront, let postEvent, let processForPID else { return false }
        var psn = [UInt32](repeating: 0, count: 2)
        guard psn.withUnsafeMutableBytes({ processForPID(pid, $0.baseAddress!) }) == 0 else { return false }
        let ok = psn.withUnsafeMutableBytes { setFront($0.baseAddress!, window, 0x200) } == 0

        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        var wid = window
        memcpy(&bytes[0x3c], &wid, MemoryLayout<UInt32>.size)
        memset(&bytes[0x20], 0xff, 0x10)
        for marker: UInt8 in [0x01, 0x02] {
            bytes[0x08] = marker
            psn.withUnsafeMutableBytes { _ = postEvent($0.baseAddress!, &bytes) }
        }
        return ok
    }

    // MARK: Native ⌘Tab

    /// Enables/disables the system's own ⌘Tab, ⌘⇧Tab and ⌘` switchers.
    static func setNativeCommandTab(enabled: Bool) {
        guard let hotKeyEnabled else { return }
        for id: Int32 in [1, 2, 6] { _ = hotKeyEnabled(id, enabled) }
    }
}
