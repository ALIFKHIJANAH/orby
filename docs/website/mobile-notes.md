# Orby website: mobile page and motion storyboard

Design file: `/Users/flaravel/Documents/Orby.pen`. Both frames reuse the variables listed in
`desktop-notes.md` (theme axis `mode`, dark by default).

## "Orby Website - Mobile" (node `A0vd7z`)

390 × 11982 at x 1640, y 2899. Same sections and copy as the desktop frame, single column,
16 px gutters, buttons and tap rows ≥ 44 px.

| Section | Node | Mobile changes |
|---|---|---|
| Status bar + nav | `ZlcmR`, `BRXsp` | Nav is wordmark + Download (44 px) + menu button (44 × 44) |
| Hero | `zGCxU` | Notch 320 × 296 with a 128 px thinking Orby; H1 48 px left-aligned; CTAs stacked full width (52 px). The scroll sequence becomes a 2 × 2 grid with a Replay button (autoplays once, 2000 ms per step) |
| Mascot states | `xMCUY` | States in 2 columns (orb 80 px), Ready/dozing spans both; tools in 3 columns (orb 64 px). Motion details point to the storyboard frame |
| Approvals | `AA9OH` | Card first, copy below; sub-points stacked with their screenshot above; trust buttons wrap to two rows |
| Agents | `Zn0Di` | Orbs in a 4 × 2 grid (52 px); the table becomes a list |
| Usage | `z2Ped` | Screenshot, then copy |
| Sounds | `sEIXK` | One cue per row, full width, 52 px tall |
| Privacy | `fdoPd` | Stat tiles stacked |
| FAQ | `UDCLW` | Question rows 44 px tall; answers 2–9 are hidden `Answer` layers |
| Final CTA, footer | `NhqYv`, `EYsRJ` | Footer links are 44 px rows |

The pencil layout checker flags many nodes in the lower half of the mobile frame as "clipped".
Exports of every section and of the whole frame render them correctly, so treat that as a checker
artifact of very tall frames, not a layout bug.

## "Orby Mascot Motion Storyboard" (node `PtKMg`)

1960 × 8615 at x 2230, y 2899. Developer handoff for animating the mascot. Each row has an info
column (loop length, easing, what moves) and 3–6 keyframe cards with the time, the computed
values and a timeline with ticks at each keyframe.

Keyframes in sections 1, 2 and 5 are drawn from a JavaScript port of `OrbPose`
(`Sources/Orby/UI/AgentOrb.swift`), evaluated at the time on the card. Body = Claude orange,
glow = phase color. Section 3 and the image-based rows use real app renders cropped from
`docs/screenshots/mascots-1/2/3.png`.

| Section | Rows |
|---|---|
| 1 · Every state | Blink · Phase-change pop · Tool double take |
| 2 · States | Thinking · Working · Compacting · Needs you · Done · Error · Ready / waiting · Dozing · Chat (two orbs) |
| 3 · Tool props | Reading · Editing · Searching · On the web · Running a command · Testing · Building · Using git · Deleting · Delegating · Planning (3 frames each) + tool rules |
| 4 · Hero scroll choreography | Scroll sequence (ready → thinking → read → edit → needs you → done, with scroll %) |
| 5 · Micro-interactions | Pointer & hover · Click & tap · Allow from the hero card |

Saccade targets in Working and Ready are fixed sample points; in the app they are pseudo-random
within the spread shown in the row.
