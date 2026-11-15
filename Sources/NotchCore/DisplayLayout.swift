import CoreGraphics

/// Which screens get an island and which island opens for a reveal. Free of AppKit so the
/// choices can be tested; the app maps `NSScreen`s to `Screen`s.
public enum DisplayLayout {
    public enum Placement: Sendable {
        /// The built-in display with a notch, else the main screen.
        case notchOrMain
        /// The screen with the menu bar.
        case menuBar
        case every
        /// Menu bar icon only.
        case none
    }

    public struct Screen: Equatable, Sendable {
        public var id: UInt32
        public var frame: CGRect
        public var hasNotch: Bool

        public init(id: UInt32, frame: CGRect, hasNotch: Bool) {
            self.id = id
            self.frame = frame
            self.hasNotch = hasNotch
        }
    }

    /// Screen ids that get an island. `screens` is in `NSScreen.screens` order, so the first one
    /// holds the menu bar; `main` is the screen with the key window.
    public static func islandScreens(_ placement: Placement, screens: [Screen], main: UInt32?) -> [UInt32] {
        let fallback = main.flatMap { id in screens.first { $0.id == id } } ?? screens.first
        switch placement {
        case .notchOrMain: return [(screens.first { $0.hasNotch } ?? fallback)?.id].compactMap { $0 }
        case .menuBar: return [(screens.first ?? fallback)?.id].compactMap { $0 }
        case .every: return screens.map(\.id)
        case .none: return []
        }
    }

    /// The one island that opens when the panel expands: the one on the screen with the pointer,
    /// else the one on the main screen, else the first. Nil only without islands.
    public static func revealScreen(islands: [Screen], mouse: CGPoint, main: UInt32?) -> UInt32? {
        // Inclusive edges: the pointer pinned to the top of a screen sits at y == maxY.
        let underMouse = islands.first { f in
            let r = f.frame
            return mouse.x >= r.minX && mouse.x <= r.maxX && mouse.y >= r.minY && mouse.y <= r.maxY
        }
        return (underMouse ?? islands.first { $0.id == main } ?? islands.first)?.id
    }
}
