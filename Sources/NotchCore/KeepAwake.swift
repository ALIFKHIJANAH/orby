import Foundation

/// When Orby holds a "don't idle-sleep" power assertion. The app owns the IOKit handle; this
/// decides when to take and release it, so the rules can be tested without touching power state.
public struct KeepAwakePolicy: Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case off, whileWorking
    }

    public enum Action: Equatable, Sendable {
        case take, release
    }

    public private(set) var held = false

    public init() {}

    /// Call on every session change and settings change. Returns what to do, or nil for nothing.
    public mutating func update(mode: Mode, anyWorking: Bool) -> Action? {
        let want = mode == .whileWorking && anyWorking
        guard want != held else { return nil }
        held = want
        return want ? .take : .release
    }

    /// On quit, never leave the Mac pinned awake.
    public mutating func stop() -> Action? {
        guard held else { return nil }
        held = false
        return .release
    }
}
