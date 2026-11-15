# Worker report: quiet + keep-awake + extra Claude config folders

## Built
1. **Follow macOS Focus** (Settings → Sounds → Quiet: "Quiet while a Focus is on", default **on**, sounds only).
   - `NotchCore/QuietHours.swift`: new `QuietRules.silencesSounds(at:screenLocked:focusOn:)` combines lock-screen mute, quiet hours and Focus. `focusOn == nil` (no permission) counts as no Focus.
   - `Orby/Services/FocusStatus.swift`: wraps `INFocusStatusCenter`. Reads `authorizationStatus` only (never prompts); asks for permission only when the user flips the toggle on or presses "Allow…" in Settings. The button is disabled when the bundle has no `NSFocusStatusUsageDescription` (e.g. `swift run`).
   - `SoundPlayer.muted` now goes through `QuietRules`. Pop-ups are unchanged.
   - `scripts/build-app.sh`: adds `NSFocusStatusUsageDescription` to Info.plist.
2. **Keep the Mac awake** (Settings → General → Power: Off / While agents work, default **Off**).
   - `NotchCore/KeepAwake.swift`: `KeepAwakePolicy` pure state machine (`update(mode:anyWorking:)` → take/release/nil, `stop()`).
   - `Orby/Services/KeepAwakeService.swift`: holds one `PreventUserIdleSystemSleep` IOPM assertion. `IslandModel.publish()` and the prefs observer call it with `workingCount > 0`; `AppDelegate.applicationWillTerminate` releases it.
3. **More Claude Code config folders** (Settings → Integrations → "More Claude Code folders": Add Folder…, Connect/Repair/Remove per folder, minus button forgets a folder after removing Orby's hooks from it).
   - `NotchCore/ClaudeConfigDirs.swift`: `ClaudeConfigDirs.extras(_:home:environment:)` expands `~`, drops blanks/duplicates and the default folders (~/.claude, $CLAUDE_CONFIG_DIR). `HookInstaller.status(claudeConfigDir:)` / `apply(claudeConfigDir:install:)`. Backups are named `claude-<folder>-settings.json.<stamp>` so folders don't collide.
   - `HookInstaller.swift`: small refactor only: `hookStatus(_:at:)` and `applyHooks(_:install:at:backupName:…)` extracted so both the default and extra folders share code; optional `name:` on `backup`.
   - Pref `claudeConfigDirs` (one path per line). Auto-configure at launch, "configure detected agents" and "Remove all agent hooks" also cover the extra folders.

## Verified
- `swift build` passes; `swift test`: **203 tests in 49 suites pass** (12 new in `Tests/NotchCoreTests/QuietAwakeConfigDirTests.swift`: Focus quiet decision ×5, keep-awake state machine ×4, multi-folder install/uninstall/unreadable in temp homes ×3).
- Ran the exact `IOPMAssertionCreateWithName(PreventUserIdleSystemSleep, …)` call in a scratch binary: it shows in `pmset -g assertions` and releases cleanly.

## Not verified
- Focus permission flow in a real bundled app. On macOS, `INFocusStatusCenter` may also need the Communication Notifications / Focus status entitlement, which an ad-hoc signed build can't carry; if so, authorization stays denied/not determined and the Focus rule simply never fires (no crash, no prompt at launch). Worth a manual check with `scripts/build-app.sh --open`.
- Settings UI was compiled but not visually checked.
