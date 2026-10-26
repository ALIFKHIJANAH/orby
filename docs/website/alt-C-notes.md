# Alt C: Terminal Native

pen.dev frame: "Orby Website - Alt C - Terminal Native" (`gUd4U`) in `~/Documents/Orby.pen`, at x=4000, y=40000, 1440 × ~10,400.

**Direction.** A near-black, developer-native page. Headlines are in JetBrains Mono and body text in Inter. The app is framed as terminal windows and tmux panes with real-looking Claude Code and Codex output. Orby peeks out of the notch in the macOS menu bar (which doubles as the nav) and reacts to those logs: each tool line in the tmux pane carries an `→ orby: <state>` tag. The hero has a 48 px grid texture. Accents follow the brief: green for done and prompts, amber/orange for needs-you, brand orange for the primary CTA, and phase colours only for state.

## Sections, top to bottom

1. **Hero.** The menu bar is the nav. The expanded notch shows Orby at the peak of its needs-you hop, with a rest-position onion-skin ring and the real permission card. HOP/LAND/REST and GLOW/GAZE/ENTER motion notes sit on either side. Below: the H1 with a block cursor, the CTAs, and a tmux window with a claude pane and a codex pane.
2. **Hero choreography.** `orby replay --hero`: a scroll track (0/15/45/70/90/100 %) and six keyframes (ready, thinking, read, search, needs you, done), each a mini notch with its notch line and timing note. The brief's three side captions sit underneath.
3. **Mascot states.** A status-legend table (`orby states --legend`) with 7 rows. Each row has keyframe A → B, the glow hex/range/period, the loop spec and the brief's line. Below it, 11 tool-prop tiles (`ls ~/.orby/props`).
4. **Approvals.** A ⌘Y / ⌘N keycap headline and the notch permission card, with Orby looking at Allow and the hover/press notes. Then three tmux panes: Questions, Plans and Trust a session.
5. **Agents.** 8 brand-colour orbs. Codex is shown in its hover/working state, with its neighbours in chat mode facing it. An `orby agents --list` capability matrix, then Jump back with terminal and editor chips next to the real `expanded-sessions.png`.
6. **Usage.** `orby usage --week`: plan-limit bars with an 85 % marker and a 7-day stacked token chart.
7. **Sounds.** A 7-key board. Each key draws its square-wave notes (width = ms, height = Hz) and the Permission request key is shown pressed. Beside the board: the needs-you orb and the quiet list.
8. **Privacy.** Three stat cells (`~2 MB`, `0`, `0`), the body copy, and a terminal listing the two opt-in network checks and `~/.orby/backups/`.
9. **FAQ.** `man orby`: a 9-item accordion with the first item open.
10. **Final CTA.** A small notch with Orby in done (wink and sparkle), the H2 and the CTAs.
11. **Footer.** Wordmark, product/ and source/ columns, legal lines, and a dozing orb as the easter egg.

## Open points

- The window titles (`orby states --legend`, `orby agents --list`, `orby usage --week`, `orby net --list`, `orby replay --hero`, `orby jump`) are decorative pseudo-commands. Orby has no CLI, so the build should either keep them obviously decorative or swap them for real commands.
- The hero has no scanline texture. A 500-stop gradient attempt rendered as grey bands and was removed. If the build wants scanlines, use a CSS `repeating-linear-gradient` there.
- The sessions screenshot is an image fill at `../Project/NotchIsland/docs/screenshots/expanded-sessions.png`, relative to the .pen file.
- The orbs are built from ellipses and rounded rects, following the "Agent Mascots" construction (radial body gradient, pill eyes at ±0.3r), with the sizes from `OrbPose`.
