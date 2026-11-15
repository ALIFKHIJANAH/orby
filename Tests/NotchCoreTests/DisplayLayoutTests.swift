import CoreGraphics
import Testing

@testable import NotchCore

private let builtIn = DisplayLayout.Screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), hasNotch: true)
private let external = DisplayLayout.Screen(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), hasNotch: false)
private let above = DisplayLayout.Screen(id: 3, frame: CGRect(x: 0, y: 982, width: 1920, height: 1080), hasNotch: false)

@Suite struct DisplayLayoutTests {
    @Test func autoPrefersTheNotchEvenWhenAnExternalHoldsTheMenuBar() {
        #expect(DisplayLayout.islandScreens(.notchOrMain, screens: [external, builtIn], main: 2) == [1])
    }

    @Test func autoWithoutANotchUsesTheMainScreen() {
        #expect(DisplayLayout.islandScreens(.notchOrMain, screens: [external, above], main: 3) == [3])
        #expect(DisplayLayout.islandScreens(.notchOrMain, screens: [external, above], main: nil) == [2])
    }

    @Test func menuBarUsesTheFirstScreen() {
        #expect(DisplayLayout.islandScreens(.menuBar, screens: [external, builtIn], main: 1) == [2])
    }

    @Test func everyDisplayGetsOneIslandEach() {
        #expect(DisplayLayout.islandScreens(.every, screens: [builtIn, external, above], main: 1) == [1, 2, 3])
    }

    @Test func menuBarOnlyHasNoIsland() {
        #expect(DisplayLayout.islandScreens(.none, screens: [builtIn, external], main: 1).isEmpty)
    }

    @Test func noScreensMeansNoIsland() {
        #expect(DisplayLayout.islandScreens(.notchOrMain, screens: [], main: nil).isEmpty)
        #expect(DisplayLayout.islandScreens(.every, screens: [], main: nil).isEmpty)
    }

    @Test func revealOpensOnTheScreenWithThePointer() {
        let islands = [builtIn, external, above]
        #expect(DisplayLayout.revealScreen(islands: islands, mouse: CGPoint(x: 2000, y: 700), main: 1) == 2)
        #expect(DisplayLayout.revealScreen(islands: islands, mouse: CGPoint(x: 100, y: 1500), main: 1) == 3)
    }

    @Test func pointerPinnedToTheTopEdgeCounts() {
        #expect(DisplayLayout.revealScreen(islands: [builtIn, external], mouse: CGPoint(x: 2000, y: 1440), main: 1) == 2)
    }

    @Test func pointerOffEveryIslandFallsBackToMainThenFirst() {
        // The pointer is on a screen that has no island (auto mode, external display).
        #expect(DisplayLayout.revealScreen(islands: [builtIn, above], mouse: CGPoint(x: 3000, y: 100), main: 3) == 3)
        #expect(DisplayLayout.revealScreen(islands: [builtIn, above], mouse: CGPoint(x: 3000, y: 100), main: 2) == 1)
    }

    @Test func noIslandNoReveal() {
        #expect(DisplayLayout.revealScreen(islands: [], mouse: .zero, main: 1) == nil)
    }
}
