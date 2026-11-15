# Multi-display and menu-bar-only mode

## What I built

- **Settings → Display → Show on** has two new choices on top of the existing two (the default, "Built-in display (notch) if available", is unchanged):
  - **Every display**: one island panel per `NSScreen`, each with its own notch metrics. Panels are added, removed and moved on `didChangeScreenParametersNotification` (display plugged in or out, arrangement or resolution change) and when the setting changes. Panels are reused where possible, so a single island that moves to another screen keeps its view state.
  - **Menu bar only (no island)**: no panel. The status item stays on even with "Show menu bar icon" off, since it's the only UI left. "Show Island" is left out of its menu. Attention still plays its sound (sound is played in `IslandModel.receive`, which doesn't depend on the panel). Any expansion is collapsed straight away, so the invisible panel's ⌘Y/⌘N/⌘1–9 shortcuts never answer a request you can't see. ⌃⌥J goes to the terminal instead of opening the notch.
- **Only one island opens.** All islands share one `IslandModel`. Each panel has its own `IslandScreen` (metrics, `isActive`, shape size), and `NotchRootView` treats `model.isExpanded && screen.isActive` as expanded. When the panel opens (attention, completion, click, ⌥⌘N, hover), the active island is the one on the screen with the pointer, else the main screen's, else the first. Hovering a collapsed island makes it the active one. While one island is open, the other islands' tabs ignore the mouse until it closes.
- Pure logic lives in `Sources/NotchCore/DisplayLayout.swift`: `islandScreens(_:screens:main:)` (which screens get an island, for each mode) and `revealScreen(islands:mouse:main:)` (which island opens). `DisplayChoice.placement` maps the setting onto it. Auto and main pick the same screens as before (first screen with a notch, else `NSScreen.main`; first screen, else main).
- Reduce motion: no new animation. The existing `reduceMotion` branches in `NotchRootView` apply to every island. Peek-on-hover only plays on the active island.

Files: `UI/NotchPanel.swift` (controller rewritten around a list of islands), `UI/NotchRootView.swift` (reads per-island metrics and active state), `App/Preferences.swift` (2 cases + `placement`), `App/AppDelegate.swift` (status item forced on, Show Island hidden), `App/IslandModel.swift` (one guard in `jumpToNeediest`), `UI/SettingsView.swift` (captions for the new modes), `App/PreviewRenderer.swift` (injects an `IslandScreen`).

## Verified

- `swift build` passes. `swift test` passes: 201 tests in 47 suites, including 10 new ones in `DisplayLayoutTests`.
- I ran the debug build on this Mac (built-in notch display plus a 1920×1080 external display above it) next to the installed Orby. I isolated it with `ORBY_HOME` pointing at a short symlink into the scratchpad (the scratchpad path is too long for a Unix socket) and the `Orby` defaults domain (separate from `dev.orby.app`). I deleted that domain and the symlink afterwards. Global shortcuts and update checks were off for the run, and no agent config was touched.
  - Every display: two panels, each centered at the top of its display (checked with `CGWindowListCopyWindowInfo`). I sent a fake Claude `PermissionRequest` through `orby-bridge` with the pointer on the external display. The log showed `reveal: island=3 of [1, 3]`, and screenshots show the request card open on the external display only, while the built-in display kept its collapsed tab with "!1".
  - auto and main: one panel on the built-in display (it holds the menu bar here), the same as before.
  - Menu bar only: no panel on screen. A permission request logged `expand(attention)` and then `collapse` straight away. With `showMenuBarIcon` set to false, the dev build's status icon still showed in the menu bar.

## Not verified

- Hot-plugging a display and rearranging displays while the app is running. The code reacts to `didChangeScreenParametersNotification` as before, but I didn't unplug the monitor.
- Changing the setting live from the Settings window. I changed it with `defaults write` and relaunched, because an external write doesn't post `UserDefaults.didChangeNotification` in the running app. The in-app path uses the same debounced observer the old `reposition()` used.
- Whether the attention sound is audible in menu-bar-only mode (the code path is unchanged; I didn't listen).
- The headphone banner shows on every island in "every display" mode. That seemed fine for a short-lived collapsed pill, but it's a choice to review.
