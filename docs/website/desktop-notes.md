# Orby website: desktop design notes

Design file: `/Users/flaravel/Documents/Orby.pen`, top-level frame **"Orby Website - Desktop"**
(node `KwWbm`), 1440 × 10519, at x 0, y 2899 (below the IG carousel row). Built from
`design-brief.md`; copy is the brief's final copy.

## Sections (top to bottom, node ids)

| Section | Node | Notes |
|---|---|---|
| Hero | `d8kDz` | Nav sits in the MacBook bezel; notch hangs from it with a large thinking Orby (primitive shapes, Claude orange, purple glow, thought dots). Includes the 4-step scroll-sequence keyframe strip (`K4Kxuc`) |
| Mascot states | `g45k8` | 7 state cards + "Every state" rules card; 11 tool-prop tiles + legend |
| Approvals | `OrzdL` | Real permission screenshot in a notch; Questions / Plans screenshots; Trust card rebuilt as UI |
| Agents | `ymgHf` | 8 agent orbs with logo badges, capability table, sessions screenshot, Jump back |
| Usage | `tOIGA` | Usage screenshot + copy |
| Sounds | `VkT5r` | 7-cue sound board (first cue shown pressed), quiet list |
| Privacy | `mUYHp` | 3 stat tiles + 3 columns |
| FAQ | `xstDo` | Accordion, item 1 open; answers 2–9 are hidden `Answer` layers (enabled: false) |
| Final CTA | `raBx2` | Small notch with Orby in done (wink + sparkle) |
| Footer | `yXDRD` | Brand, two link columns, legal line, tiny ready orb |

Motion intent is written in lavender mono "Motion Note" chips next to the element they describe.
They are annotations for developers, not page content: hide them in a production comp.

## Variables (for the mobile frame)

Theme axis `mode` with values `dark` (default; the desktop frame sets `theme: {mode: "dark"}`)
and `light`. To make the light variant, copy a frame and set `theme: {mode: "light"}`.

- Surfaces and text (themed): `bg`, `bg-grad-top`, `bg-grad-mid`, `bg-elev`, `stroke`, `text`,
  `text-2`, `text-3`, `orby-orange`, `on-orange`, `lavender`, `focus`
- Fixed: `notch`, `card`, `card-hover`, `card-mascot` (#141414, matches the mascot sheet
  background), `orby-orange-hi`, `orby-orange-lo`
- Phase colors (fills): `thinking`, `working`, `attention`, `done`, `error`, `idle`; text-safe
  themed versions: `thinking-text`, `working-text`, `attention-text`, `done-text`, `error-text`
- Agent body colors: `agent-claude`, `agent-codex`, `agent-antigravity`, `agent-opencode`,
  `agent-pi`, `agent-commandcode`, `agent-qwen`, `agent-cursor`
- Type: `font-display` (Inter Tight), `font-body` (Inter), `font-mono` (JetBrains Mono); sizes
  `h1-size` 88, `h2-size` 56, `h3-size` 24, `body-l-size` 21, `body-size` 17,
  `caption-size` 13, `mono-size` 15 (mobile sizes are in the brief §5.2)
- Spacing `space-1` … `space-40` (4 → 160), radius `radius-sm` 6, `radius-md` 12,
  `radius-lg` 20, `radius-xl` 28, `radius-pill` 999

## Assets and reuse

- Mascot poses are image crops of `docs/screenshots/mascots-2.png` (real app renders). Each crop
  is a 250 px square around an orb: column centers x = 180 + 284·col, row centers y = 180 / 500 / 823,
  fill transform `[7.12, 0, 0, 4.2, -(cx-125)/250, -(cy-125)/250]`. Sheet layout (col,row):
  read 0,0 · web 1,0 · build 2,0 · delegate 3,0 · approval 4,0 · compacting 5,0 · edit 0,1 ·
  run 1,1 · git 2,1 · plan 3,1 · done 4,1 · ready 5,1 · search 0,2 · test 1,2 · delete 2,2 ·
  thinking 3,2 · error 4,2 · dozing 5,2. Put crops on `card-mascot` (#141414) so the square
  doesn't show.
- Large orbs (hero, agents row, final CTA, footer) are built from ellipses and rectangles like
  the existing "Agent Mascots" frame; agent logos are the 24×24 paths from
  `Sources/Orby/UI/AgentLogos.swift`.
- UI screenshots come from `docs/marketing/assets/` (cropped black panels), referenced
  relative to the .pen file as `../Project/NotchIsland/docs/marketing/assets/…`.
- The notch silhouette is a path with concave top flares (`NotchShape` in Theme.swift):
  `M0 0 Q t 0 t t L t H-b Q t H t+b H L W-t-b H Q W-t H W-t H-b L W-t t Q W-t 0 W 0 Z`.

## Deviations from the brief

- The FAQ got an H2 ("Before you download.") so the section has a heading like the others.
- The working-state card uses the "web" pose (no plain working pose exists in the mascot sheet).
- The Trust sub-point is a rebuilt button row instead of `expanded-edit.png`, which has no
  cropped version.
