# Orby website: design brief

For the designer building the Orby landing page in pen.dev. One page, dark first, with the
animated Orby mascot as the hero.

Sources this brief is built from (read them if something here is unclear):

| What | Where |
|---|---|
| Product spec | `README.md`, `docs/FEATURES.md` |
| Competitor research | `docs/research/competitors.md` (sections 3 and 4 especially) |
| Mascot motion (source of truth) | `Sources/Orby/UI/AgentOrb.swift` (`AgentOrb`, `AgentMascot`, `OrbPose`) |
| Colors | `Sources/Orby/UI/Theme.swift`, `docs/design/AppIcon-1024.png` |
| Existing visuals | `docs/screenshots/*.png` (UI states, `mascots-1/2/3.png` = every pose), `docs/marketing/ig-carousel/*.png` + `caption.txt` |

Everything the copy claims is in the README or FEATURES.md. Section 8 lists the facts that still
need an owner's confirmation before launch (license, download hosting, signing).

---

## 1. Positioning

**One-line pitch:** Orby is a Dynamic Island for your AI coding agents. It lives in the MacBook
notch and shows what each agent is doing, so you can approve, answer and jump back without
switching windows.

**Positioning statement:** For developers who run several coding agents at once, Orby is the
notch app that shows every session's state at a glance and lets you act on it from the top of
the screen. Unlike Vibe Island ($19.99) or AgentNotch ($9.99), it is free, about 2 MB of native
Swift, needs no account, and never overwrites your config.

**Audience, in priority order**

1. Developers on a MacBook with a notch who run Claude Code or Codex in 2+ terminals and lose
   track of which one is waiting on them.
2. People trying several agents (OpenCode, Qwen Code, Pi, Command Code, Antigravity, Cursor) who
   want one place to see all of them.
3. People who tried a rival notch app and left over noise, CPU use, duplicate prompts or a
   clobbered `statusLine`.

**CTAs**

| | Label | Meta line under it | Target |
|---|---|---|---|
| Primary | **Download for macOS** | Free · macOS 14 or later · about 2 MB | The latest `Orby-x.y.z.dmg` (see section 8) |
| Secondary | **View on GitHub** | none | `https://github.com/ALIFKHIJANAH/orby` |

The primary button is always the filled one. Never put two filled buttons side by side.

**Voice:** plain, specific, a little dry. Name the agent, the key, the file. Say what happens, not
how it will make you feel. No "supercharge", "seamless", "unleash", "game-changer", no stacked
adjectives, no exclamation marks. The mascot carries the warmth so the copy doesn't have to.

---

## 2. What to take from competitor sites

From `docs/research/competitors.md`. Names refer to the products in that file.

**Do what works**

- **Show the notch doing the job, above the fold.** Vibe Island and Claude Island get their
  praise from the moment approve/deny pops out of the notch ("one click, no window switching",
  @dotey on X). Our hero must show a real permission card opening from the notch, not a
  feature list.
- **Let the delight features be seen and heard.** Users quote sound effects (Vibe Island:
  "obsessed with the sound effects") and mascots (Notchi, AgentNotch) in their own words.
  Section 3 makes the mascot the hero and gives sounds their own playable section.
- **Agent logos as proof.** Every rival's most-requested feature is "support agent X". A logo row
  with an honest "what works from the notch" table answers that faster than prose (Vibe Island
  claims 30 agents; Ping Island lists about 15).
- **Real UI, real commands.** AgentNotch and Notchy lead with the full command shown before
  approving. Use our actual screenshots and real commands (`rm -rf node_modules && pnpm
  install`), not lorem ipsum.
- **A short, specific comparison.** `docs/FEATURES.md` already compares Vibe Island, AgentNotch
  and Orby. Pull 4–5 rows into the FAQ instead of a full matrix.

**Avoid what users punish**

- **Noise in the page itself.** Users report forced popups and a sound on every tool call (Vibe
  Island #42, #114; Ping Island #122). The site must not autoplay audio, must not open modals, and
  must not loop a fast animation in the reader's peripheral vision while they read copy.
- **Heavy pages for a "lightweight" app.** Ping Island, Open Vibe Island, Notchy and CodexBar all
  draw CPU, heat and RAM complaints. A 2 MB app with a 20 MB landing page undercuts the claim.
  Budget: under 1.5 MB transferred on first load, mascot drawn with code (canvas/SVG), not video.
- **Vague privacy.** Vibe Island lost trust over a keychain dump (#216) and overwriting
  `statusLine` (#137, #107); Claude Island ships Mixpanel. Say exactly which network calls exist,
  and that they're opt-in.
- **"74 modules" sprawl.** Notchy's praise is about non-agent features and its complaints are
  "bloatware". Stay on one job: agents in the notch.
- **Claims we can't back.** No agent counts we don't support, no CPU numbers we haven't measured
  (competitors.md gap #4: Orby has not published CPU/RAM numbers yet).

**How Orby differs (say these, in this order)**

1. **The mascot acts out the work.** Notchi has per-state sprites and AgentNotch a mascot beside
   the notch; Orby's orb takes the agent's brand color and acts out the current tool (holds a
   page while reading, swings a magnifier while searching, stomps while building).
2. **Thinking is its own state,** with the latest reasoning line. AgentNotch doesn't have it.
3. **Free, ~2 MB native, no account, no telemetry.** Vibe Island is $19.99, AgentNotch $9.99.
4. **Leaves your config alone.** Hook edits are additive, backed up to `~/.orby/backups/` first,
   and Orby only removes files it wrote.
5. **Polite by default.** Never steals focus, stays quiet when you're already looking at that
   terminal, quiet hours, mute while locked.

---

## 3. Sitemap and final copy

One scrolling page. Sections in order, top to bottom. Copy below is final; the designer may
shorten for fit but should not add claims.

Asset names in `code` refer to files in `docs/screenshots/` unless stated.

### 3.0 Navigation (sticky)

- Left: wordmark. An orange dot (`--orby-orange`) plus "orby" in lowercase, as on the IG carousel.
- Links: **How it works** · **Agents** · **Privacy** · **FAQ**
- Right: ghost link **GitHub** · small filled button **Download**
- Behavior: transparent over the hero; after 80 px of scroll, background `--bg-elev` at 80% with a
  12 px backdrop blur and a 1 px bottom border `--stroke`.

### 3.1 Hero

Layout: a MacBook-top bezel spans the width with the notch centered at the very top of the
viewport. Orby sits *in* the notch and the notch grows as the hero choreography plays (section 4.4).

- Eyebrow: `For Claude Code, Codex and 6 more agents`
- **H1:** Your AI agents, in the notch.
- Subcopy: Orby lives in your MacBook's notch and shows what every coding agent is doing:
  thinking, working, done, or waiting on you. Approve tool calls, answer questions and jump back
  to the right terminal without leaving what you're doing.
- Primary CTA: **Download for macOS** — meta: `Free · macOS 14 or later · about 2 MB`
- Secondary CTA: **View on GitHub**
- Under the CTAs, a single small line: `No Mac notch? Orby becomes a floating bar.`
- Hint under the fold line (fades out on first scroll): `Scroll to give Orby some work ↓`

### 3.2 Mascot moods and states

- Eyebrow: `Meet Orby`
- **H2:** One look tells you what the agent is doing.
- Subcopy: Orby takes the color of the agent it's watching and acts out the current step. It
  holds a page while it reads, types while it edits, and hops when it needs you.
- Block A, "States", 7 tiles. Each tile: the live orb (section 4.2), a label, one line.

  | Tile label | Line |
  |---|---|
  | Thinking | Eyes roll up, a thought bubble puffs. The notch shows the latest reasoning line. |
  | Working | Quick glances and a restless bob. The current tool is on the line below. |
  | Compacting | Squinting and squeezing while the agent shrinks its context. |
  | Needs you | Hops and glows orange: a permission, a question, or a plan to review. |
  | Done | A wink and a sparkle. |
  | Error | Droops and shakes its head. |
  | Ready / dozing | Looks around, breathes. Left alone for 3 minutes, it falls asleep. |

- Block B, "What it's doing", 11 small tiles, one per tool prop (section 4.3). Label only:
  Reading · Editing · Searching · On the web · Running a command · Testing · Building ·
  Using git · Deleting · Delegating to subagents · Planning
- Caption under block B: `Every tool the agent runs maps to one of these. Subagents show up as
  little orbs circling the main one.`
- Reference image: `mascots-1.png`, `mascots-2.png`, `mascots-3.png` show every pose at rest.

### 3.3 Approvals from the notch

Two-column on desktop: copy left, the real permission card right (`expanded-permission.png`,
rebuilt as live UI so the buttons respond to hover).

- Eyebrow: `Approvals`
- **H2:** Allow it with ⌘Y. Deny it with ⌘N.
- Subcopy: When an agent asks to run a command, the notch opens with the full command and a
  warning if it deletes files or does something risky. Allow, deny, always allow, or hand it back
  to the terminal.
- Three sub-points, each with a small screenshot:
  1. **Questions.** Answer the agent's multiple-choice and free-text questions right in the
     notch. (`expanded-question-multi.png`)
  2. **Plans.** Read the plan as formatted Markdown. Approve it, approve and auto-accept edits,
     or send feedback. (`expanded-plan.png`)
  3. **Trust a session.** "Allow, and trust this session for 30 min" auto-allows its next safe
     requests. Anything risky, every question and every plan still asks. (`expanded-edit.png`)
- Footnote line: `Answered in the terminal instead? The card clears itself.`
- Micro-interaction: hovering **Allow** makes the hero-style orb in the card look at the button;
  clicking plays the done pop (section 4.5).

### 3.4 Multi-agent support

- Eyebrow: `Agents`
- **H2:** Eight agents, one notch.
- Subcopy: Click Connect once per agent in Settings. Orby adds its hook, backs up your config
  first, and removes only what it wrote.
- Logo row: 8 `AgentMascot` orbs (orb in brand color with the logo badge on its shoulder), in
  this order, each with its name below: Claude Code, Codex, OpenCode, Qwen Code, Command Code,
  Pi, Antigravity, Cursor. On hover, the hovered orb plays its "working" loop; neighbours turn
  their eyes toward it (chat behaviour, section 4.2).
- Table under the row (keep it; it's the honest answer to "does it work with X"):

  | Agent | From the notch |
  |---|---|
  | Claude Code | Status, approvals, questions, plans |
  | Codex | Status, approvals |
  | OpenCode | Status, approvals, questions |
  | Qwen Code | Status, approvals |
  | Command Code | Status, approvals |
  | Antigravity | Status, prompt alerts it can answer by typing into the terminal |
  | Pi | Status |
  | Cursor | Status |

- Second line under the table: **Jump back.** Click a session to focus its iTerm2 session,
  Terminal tab, tmux pane, Kitty or WezTerm pane, or the VS Code, Cursor, Windsurf or Zed window
  holding the project.
- Screenshot: `expanded-sessions.png` (sessions grouped by project with branch and worktree).

### 3.5 Usage

- Eyebrow: `Usage`
- **H2:** See your limits before you hit them.
- Subcopy: Codex and Claude 5-hour and weekly limits, Antigravity limits per model group, and a
  7-day token chart stacked per agent. Read from the agents' own local files.
- Bullets:
  - The header shows the two limits closest to running out, or up to three you pick.
  - A chime when a session's context window passes 85%.
  - Claude and Antigravity limits are opt-in and off by default.
- Screenshot: `expanded-usage.png`.

### 3.6 Sounds

- Eyebrow: `Sounds`
- **H2:** Hear when it needs you. Hear nothing when it doesn't.
- Subcopy: Short 8-bit cues for each event, macOS system sounds, or a folder of your own. Turn
  each event on or off.
- Sound board: 7 buttons, each plays the cue in the browser (Web Audio square wave, notes in
  section 4.6). Labels: Permission request · Question · Plan ready · Task complete · Error ·
  Session start · Context almost full. The orb next to the board plays the matching state while
  the cue plays.
- "Quiet" list beside the board:
  - Quiet when you're already looking at that terminal
  - Quiet hours, and mute while the screen is locked
  - Optional reminder if a request sits unanswered for 2, 5 or 10 minutes
- Small print: `Sounds on this page only play when you press a button.`

### 3.7 Privacy and native

- Eyebrow: `Privacy`
- **H2:** About 2 MB. No account. Nothing leaves your Mac.
- Three stat tiles (number large, label small):
  - `~2 MB` — native Swift app
  - `0` — accounts, sign-ups or analytics
  - `0` — config files overwritten
- Body: Orby reads your agents' local transcripts and talks to them over a local socket. The only
  network requests are ones you turn on: the Claude plan-limit check, and the Antigravity quota
  check that `agy` makes with your own sign-in.
- Second paragraph: If Orby isn't running, or anything fails, the hook exits quietly and your agent
  shows its normal terminal prompt. Delete the app and the hooks become harmless no-ops.
- Third paragraph: Every hook change is additive, with a timestamped backup in `~/.orby/backups/`.

### 3.8 FAQ

Accordion, first item open. Final copy:

1. **Do I need a MacBook with a notch?**
   No. On Macs without one, or on an external display, Orby shows as a floating bar at the top of
   the screen.
2. **Which macOS version?**
   macOS 14 Sonoma or later.
3. **What does it cost?**
   Nothing. No trial, no license key, no account.
4. **Does it send my code anywhere?**
   No. Orby reads local files and listens on a local socket. The two network requests it can make
   (Claude plan limits, Antigravity quota) are off until you turn them on.
5. **What happens if Orby isn't running?**
   Your agent doesn't notice. The hook exits without output and the agent asks in the terminal as
   usual.
6. **Will it steal focus while I type?**
   No. Orby never takes focus from the app you're in, and it stays quiet when you're already
   looking at that agent's terminal.
7. **I already use Vibe Island. Can I run both?**
   Yes, but if both are hooked into the same agent, both show every permission request. Disconnect
   that agent in one of them.
8. **Which terminals can it jump back to?**
   iTerm2, Terminal, tmux, Kitty and WezTerm go to the exact tab or pane. VS Code, Cursor,
   Windsurf and Zed go to the window holding the project. Other apps are brought to the front.
9. **How do I remove it?**
   Click **Remove all agent hooks** in Settings (or Remove next to each agent in Integrations), then
   delete the app. Backups of your original config are in `~/.orby/backups/`.

### 3.9 Final CTA

Centered. Orby in the **done** state (wink + sparkle) sits in a small notch above the headline.

- **H2:** Your notch has done nothing since 2021. Give it a job.
- Subcopy: Download Orby, click Connect for your agents, and restart their sessions.
- Primary: **Download for macOS** — meta `Free · macOS 14 or later · about 2 MB`
- Secondary: **View on GitHub**

### 3.10 Footer

- Left: wordmark + `A Dynamic Island for your AI coding agents.`
- Columns:
  - **Product:** Download · Changelog (GitHub Releases) · Features (link to `docs/FEATURES.md` on GitHub)
  - **Source:** GitHub · Report an issue
- Bottom line: `Made for macOS. Not affiliated with Apple, Anthropic, OpenAI or Google.` and
  `© 2026 Orby`.
- Tiny ready-state orb at the bottom right that dozes after 20 s with no pointer movement
  (Easter egg; section 4.5).

---

## 4. Mascot motion spec

### 4.1 Anatomy and global rules (apply to every state)

All numbers come from `OrbPose` in `AgentOrb.swift`. **r** = orb radius. Times are in ms.

- **Body:** a flat circle in the agent's brand color (section 5.1). The hero uses Claude orange
  `#D97857`; the app icon uses the shaded version `#F59D7B → #DF714C → #C05537` (radial, light from
  lower left). Flat for UI-size orbs, shaded allowed at ≥ 120 px.
- **Eyes:** two vertical pills, `0.28r` wide × `0.56r` tall, fully rounded, centered `±0.3r` from
  the middle and `0.1r` above it. White, except **black** on light bodies (Codex, Command Code,
  Cursor). Eyes move with the gaze up to `0.42r` sideways and `0.38r` vertically; the eye on the
  side being looked toward gets 28% shorter and 15% narrower (foreshortening), and both eyes tilt
  up to 55° when looking diagonally. Below 30% open, an eye widens 20% and turns into a slit.
- **Glow:** a radial gradient behind the body in the **phase color** (not the brand color), from
  `0.85r` (opacity = glow × 0.8) to `1.45r` (opacity 0). Glow strength per state below.
- **Pivot:** squash and stretch scale from the **bottom** of the orb, so landings look grounded.
  Tilt rotates around the center.
- **Canvas:** draw on a `2r × 2r` margin around the orb (the frame is 2× the orb) so hops and
  props can leave the circle.
- **Blink (all states except dozing):** one blink at a random moment in every 4200 ms window.
  Close and reopen take 80 ms each (linear). 25% of blinks are doubles, the second 220 ms after
  the first.
- **Gaze darts ("saccades"):** hold a target, then move to the next in 140 ms with smoothstep
  easing (CSS `cubic-bezier(0.45, 0, 0.55, 1)`).
- **Phase-change pop:** on every state change, 450 ms sine bump (`sin(π·t/450)`): body +16%,
  eyes +20%, eyes forced fully open at the peak.
- **Tool-change double take:** when the tool changes while working, 300 ms: body 7% wider and 5%
  shorter, eyes +12%.
- **"Pop in" easing** for check marks: back-out with overshoot 2.2, close to CSS
  `cubic-bezier(0.34, 1.7, 0.64, 1)`.
- **Oscillations** are pure sines (ease-in-out, yoyo). Periods below are full cycles.
- **Frame rate:** 30 fps for working, thinking and needs-you; 15 fps for calm states; 7.5 fps
  while dozing. On the site, pause any orb that is scrolled out of view.
- **Reduced motion** (`prefers-reduced-motion: reduce`): no hops, bobs, tilts, squash or gaze
  movement, props frozen in place. Blinks and color/glow still show the state. Same rule as the
  app.

### 4.2 States

| State (`SessionPhase`) | Glow (phase color) | Pose and props | Loop |
|---|---|---|---|
| **thinking** | `#B38FFF` purple, 0.15–0.55, period 3490 | Eyes 80% open, 92% size, looking up (gaze y −0.6). Thought bubble: 3 purple dots rising up and to the right at `(0.95r, −0.75r)` size `0.11r`, `(1.2r, −1.05r)` `0.15r`, `(1.5r, −1.32r)` `0.19r`. | Eyes roll left↔right along the top, ±0.7, period 6980, with a small vertical wobble (period 3490). Head tilts ±7° in step with the eyes (period 6980). Floats ±0.05r (period 4190). Thought dots light in sequence like "…": each dot's cycle is 625 ms, staggered by ~206 ms, opacity 0.35→1, size 85%→100%, eased sin². |
| **working** | `#5C9EFF` blue, 0.15–0.75, period 1960 | Eyes fully open, gaze biased upward. If a tool is known, adds that tool's pose and prop (section 4.3), which override gaze/bob/tilt. | Gaze darts every 550 ms within ±0.75 x, ±0.3 y around a point 0.25 above center. Bob ±0.06r, period 2090. Tilt ±6°, period 4490. |
| **compacting** | `#5C9EFF` blue, as working | Same as working, but eyes 30% open (slits). | Working loop plus squash/stretch ±6%, period 2620 (squeezing itself smaller). |
| **needsApproval / needsAnswer / planReview** ("Needs you") | `#FF9E33` orange, 0.55–0.95, period 1260 | Looks **down at the viewer** (gaze y +0.55), eyes 115% size. | 1600 ms hop cycle: 0–480 ms jumps `0.22r` up and stretches 8% tall (sine arc); 480–640 ms lands with a 10% squash (sine); 640–1600 ms rests. Eyes sway ±0.1 x, period 4830. Glow pulses fast. |
| **done** | `#4DD980` green, steady 0.35 | Glances up-right (0.4, −0.4). Four-point sparkle star (pinched sides) in the **body color** at `(1.05r, −0.95r)`, max size `0.32r`. | Tilt ±4°, period 5240. Bob ±0.04r, period 2620. Every 3200 ms the **right eye winks** from 500 to 900 ms (a happy upward arch). Sparkle grows and shrinks on a sin² curve every 1600 ms. |
| **error** | `#FF5C5C` red, steady 0.55 | Droopy: eyes 45% open, looking down (gaze y +0.45). | Every 3200 ms, a 500 ms head shake: ±0.08r side to side at ~6.4 Hz, amplitude decaying linearly to 0. Otherwise still. |
| **ready / waitingInput** | none (idle `#FFFFFF` at 35%) | Eyes fully open, looking around. | Gaze darts every 1900 ms within ±0.6 x, ±0.45 y. Breathing: squash ±2.5% and float ±0.03r together, period 3700. |
| **dozing** (ready/waitingInput idle > 180 s in the app; use 20 s on the site) | none | Eyes shut as soft downward arcs, gaze slightly down, head tilted 5°. Three white "z" glyphs (heavy, rounded) drift up-right. | Deep breaths: squash ±4.5% with float ±0.04r, period 5710. Each z rises from `(0.85r, −0.65r)` to `(1.35r, −1.5r)` in 2220 ms, scale 0.45→0.8, opacity `0.8·sin(π·p)`; the three are staggered by a third of the cycle. Any phase change wakes it with the 450 ms pop. |
| **chat** (two orbs side by side, used in 3.4) | as the underlying state | Both orbs stop moving and face each other (gaze 0.8 toward the partner). | They take turns every 600 ms. The speaker's eyes flap in a talking rhythm: openness −35% and size +12% on `|sin(11t)|` (~286 ms per flap) and nudge upward. The listener holds still. |

### 4.3 Tool props (working state only)

Each prop is the working state plus the pose below. Accent = working blue `#5C9EFF` (the phase
color). Check marks use done green `#4DD980`. Props marked "held" move with the orb's tilt and
squash; the rest stay in world space.

| Tool (`ActivityKind`) | Pose | Prop | Loop |
|---|---|---|---|
| **read** | Eyes 85%, looking down at the page, tilt −3 ±2° (period 7850), float ±0.02r (period 3140). | Held page: off-white `#F7F7F7` rounded rect `1.24r × 0.76r`, corner `0.1r`, 4% black outline, held `0.82r` below center, rotated −6°. Three grey `#C7C7C7` lines (third is 62% long). | 1200 ms per line: the current line fills with accent over 984 ms while the eyes sweep left→right, then the eyes snap back in 216 ms and drop a line. 3 lines, then repeat. |
| **edit** | Eyes 70% (focused), gaze following the caret, tilt −2°. | Same held page. Lines already written are `#8C8C8C`, the current one grows in accent with a black caret after it. | 1600 ms per line, 3 lines. Caret blinks every 524 ms. Typing bob: 0.03r down + 3.5% squash on `|sin(10t)|` (~314 ms per tap). |
| **search** | Eyes 120%, tilt ±9° following the lens. | Held magnifier: ring radius `0.34r`, `#F2F2F2` rim, 22% white glass, dark `#333333` handle down-right, a white glint arc. | Lens and eyes trace a figure eight across the face (`x = 0.8 sin a`, `y = 0.3 sin 2a + 0.1`), period 3700. Float ±0.03r at double speed. |
| **web** | Floating, eyes tracking the satellite. | A blue satellite dot (`0.17r`) with a 6-dot fading trail on a tilted elliptical orbit (`1.45r × 0.42r`, tilted −15°). It passes **behind** the orb on the far side. | One orbit every 2990 ms. Float ±0.07r, period 4830. Tilt ±5° with the orbit. |
| **run** | Leans in (tilt −7°), looking right, eyes 85%. | Three white speed lines behind (left) at y `−0.35r`, `0.05r`, `0.45r`, length 0.3–0.65r, opacity 25–55%. | Jogs on the spot: a hop every 385 ms, `0.13r` high; first 15% of each cycle is a 9% landing squash, then a 5% stretch in the air. Speed lines flicker independently (~700 ms). |
| **test** | Eyes 50% (scrutinizing), 105% size, slow scan ±0.6 x (period 6980). | A green check mark at `(1.2r, −0.95r)`, size `0.32r`, stroke `0.12r`, round caps. | 1400 ms cycle: a 0.06r nod in the first 280 ms while the check pops in with overshoot; it holds, then fades from 1050 to 1400 ms. |
| **build** | Eyes 60%, looking slightly down-right. | Dust: two white puffs each side of the base, 55% opacity, spreading outward and fading. | 800 ms hammer: 0–480 ms rises `0.16r` and rocks back to −8° with a 5% stretch (ease-out sine); 480–560 ms slams down (linear); 560–800 ms squash 14% → 0 while the dust puffs fly out. |
| **git** | Looks right at the lit commit, tilt 4°. | A vertical branch at `x = 1.45r` from `−0.6r` to `0.6r` (white 30%), three commit nodes (`0.11r`, white 45%). | Every 550 ms the next node lights in accent and grows to `0.18r`, with a ring expanding `0.25r` and fading over 330 ms. The orb hops `0.08r` in the first 165 ms of each. Top to bottom, repeat. |
| **delete** | Wincing: eyes 38%, 4% squashed. | Three white square crumbs (`0.1r`) falling from the lower right, spinning, accelerating (falls with gravity), fading. | Crumbs cycle every 1110 ms, staggered by a third. Every 1200 ms a 350 ms nervous shiver: ±0.05r at ~9.5 Hz, decaying. |
| **delegate** | Eyes 105%, gaze circling with the helpers. Bob ±0.04r (period 3140). | 1–3 mini orbs (one per subagent, max 3) at `0.3r`, in the same body color with blinking dot eyes, each bobbing (~1050 ms). They orbit on the same tilted ellipse as *web* and pass behind the main orb. | One orbit every 4190 ms, helpers evenly spaced. |
| **plan** | Looking up-left, eyes 85%, tilt ±6° (period 8980), float ±0.04r (period 4490). | A three-item checklist at `x = 1.25r`, boxes `0.28r`, white 50% outline, corner `0.06r`. | 3000 ms cycle: green checks pop in with overshoot at 450, 1110 and 1770 ms (240 ms each), hold, then all clear at 3000 ms. |

### 4.4 Hero choreography (scroll-driven)

The hero pins for about 220 vh of scroll on desktop. Orby is large (section 6) and sits in a
notch at the top center. Under the orb, a notch "status line" in mono shows what's happening.
Each state change plays the 450 ms phase pop; each tool change plays the 300 ms double take.
Scrolling back up reverses through the same states.

| Scroll progress | Orby | Notch | Copy on screen |
|---|---|---|---|
| 0% (load) | **ready**: looking around, breathing, blinking. After 400 ms, one glance down at the H1. | Collapsed pill, the size of the real notch. | Hero copy (3.1) |
| 0–15% | → **thinking**: thought dots, purple glow. | Grows to one line: `Thinking: the login redirect loops because the cookie is set after the 302…` (purple italic, like the app). | Hero copy fades to 40% |
| 15–45% | → **working**, tools in sequence, ~7.5% scroll each: **read** → **search** → **edit** → **test** | One line per tool: `Reading auth/session.ts` → `Searching "Set-Cookie"` → `Editing session.ts` → `$ pnpm test` | Side caption: `Orby acts out the tool the agent is running.` |
| 45–70% | → **needsApproval**: hops, orange glow, eyes look down at the card. | Expands into the real permission card: `Claude wants to reinstall dependencies`, `$ rm -rf node_modules && pnpm install --frozen-lockfile`, red `Deletes files` label, **Deny ⌘N** · **Always allow** · **Allow ⌘Y**. | Side caption: `It asks. You answer from the notch.` |
| (interaction) | If the user clicks **Allow** or presses ⌘Y/Ctrl+Y here: → **working / run** for 1200 ms → **done**. Without a click, scrolling past 70% auto-allows. | Card collapses back to one line: `$ pnpm install` | none |
| 70–90% | → **done**: wink, sparkle, green glow. | One line: `Done · Fixed the OAuth redirect loop` with a green check | Side caption: `And tells you when it's done.` |
| 90–100% | Stays **done**, then eases to **ready** as the pin releases. | Collapses to the pill. | Next section scrolls in |

Rules:

- Scroll position picks the state; the loops themselves run on time, not on scroll. Never scrub a
  loop with the scroll wheel.
- If the reader stops scrolling for 20 s inside the hero, Orby dozes (section 4.2). Any scroll or
  pointer move wakes it with the phase pop.
- **Reduced motion:** no pin. Show a static 4-frame strip (thinking, working with the edit page,
  needs you with the card, done) with captions.
- **Mobile:** no pin (section 6.2). The same sequence autoplays once when the hero is in view,
  2000 ms per step, and can be replayed with a small "Replay" text button.

### 4.5 Hover, click and tap micro-interactions

- **Eyes follow the pointer** on every large orb (hero, final CTA): gaze = vector from the orb's
  center to the pointer, divided by 400 px, clamped to length 1, moved with the 140 ms saccade
  easing. When the pointer leaves the window, return to the state's own gaze.
- **Hover the hero orb:** eyes widen 10% and glow +0.15 (200 ms ease-out).
- **Click/tap the hero orb:** plays the phase pop and skips to the next state in the
  choreography. Five quick clicks in 2 s: it gets dizzy (error head-shake once) then returns.
- **State tiles (3.2):** each tile plays its loop only while hovered or focused; at rest it shows
  the state's first frame. On touch, tap toggles play.
- **Agent row (3.4):** hovered orb switches to working; the two neighbours use the **chat**
  behaviour toward it.
- **Approve button (3.3):** hover → the card's orb looks at the button; press → done pop + wink.
- **Sound board (3.6):** pressing a cue plays the matching state on the board's orb for the
  length of the cue + 600 ms, then back to ready.
- **Download button:** on hover the nav's tiny orb (if shown) looks at it. No bounce on the button
  itself.
- **Footer orb:** dozes after 20 s of no pointer movement, wakes on movement.
- **Keyboard focus** gets the same reactions as hover. Focus ring: 2 px `--focus` outside the
  element with 2 px offset.

### 4.6 Sound cues for the web sound board

From `SoundPlayer.swift`: square wave, short decay per note, 120 ms silent lead-in. Frequency in
Hz, duration in ms, 0 Hz = rest.

| Cue | Notes |
|---|---|
| Permission request | 880/70, 1175/90, rest/60, 880/70, 1175/120 |
| Question | 784/80, 988/80, 1319/140 |
| Plan ready | 659/90, 880/90, 1109/160 |
| Task complete | 523/70, 659/70, 784/70, 1047/180 |
| Error | 440/110, 349/110, 262/220 |
| Session start | 1047/50, 1568/80 |
| Context almost full | 988/80, rest/50, 988/80, 784/160 |

### 4.7 Delivery notes for pen.dev and build

- In pen.dev: design each state as a frame with the orb at its key pose (the peak of the loop:
  hop top for needs you, wink for done, mid-sweep for read) plus a second frame for the other
  extreme, and annotate with the loop numbers from this section.
- In code: don't export video or Lottie. `OrbPose` is a pure function of time, so the build should
  port it to a ~300-line canvas (or SVG) function with the same numbers. That keeps the page
  small and the motion identical to the app.

---

## 5. Visual system

### 5.1 Color tokens

**Dark (default)**

| Token | Hex | Source / use |
|---|---|---|
| `--bg` | `#0C091A` | Page background (IG carousel bottom) |
| `--bg-grad-top` | `#281D54` | Hero radial glow, from the app icon background |
| `--bg-grad-mid` | `#181134` | Section backgrounds, alternating with `--bg` |
| `--bg-elev` | `#130D28` | Raised sections, sticky nav (icon bottom) |
| `--notch` | `#000000` | The notch, the panel and app screenshots (`Theme.surface`) |
| `--card` | `#121212` | Cards inside the notch (`Theme.card`, white 7% on black) |
| `--card-hover` | `#1F1F1F` | (`Theme.cardHover`, white 12% on black) |
| `--stroke` | `#FFFFFF` at 10% | Borders, dividers (`Theme.stroke`) |
| `--text` | `#F4F1FF` | Headlines and body (carousel headline color) |
| `--text-2` | `#A9A3C4` | Subcopy, captions |
| `--text-3` | `#8B85A7` | Meta lines, footer (5.6:1 on `--bg`) |
| `--orby-orange` | `#DF714C` | Brand: wordmark dot, primary button fill (app icon orb mid-tone) |
| `--on-orange` | `#15102E` | Primary button label in dark mode (5.8:1). White on this orange is only 3.2:1 |
| `--orby-orange-hi` | `#F59D7B` | Orb highlight, button hover |
| `--orby-orange-lo` | `#C05537` | Orb shadow, button pressed |
| `--lavender` | `#C4B5FD` | Thought dots in the icon, links, focus ring (`--focus`) |

**Phase colors** (`Theme.swift`; use only for state, never for decoration)

| Token | Hex | Phase |
|---|---|---|
| `--thinking` | `#B38FFF` | thinking |
| `--working` | `#5C9EFF` | working, compacting; tool prop accents |
| `--attention` | `#FF9E33` | needs approval, question, plan ready |
| `--done` | `#4DD980` | done; check marks; Allow button |
| `--error` | `#FF5C5C` | error; Deny button outline; "Deletes files" label |
| `--idle` | `#FFFFFF` at 35% | ready, waiting |

**Agent brand colors** (orb body fill; `Theme.color(for: agent)`)

| Agent | Hex | Eyes / logo ink |
|---|---|---|
| Claude Code | `#D97857` | white |
| Codex | `#E6E6F2` | **black** |
| Antigravity | `#4285F5` | white |
| OpenCode | `#29BDAD` | white |
| Pi | `#ED5C9E` | white |
| Command Code | `#A3DB4D` | **black** |
| Qwen Code | `#7A66F5` | white |
| Cursor | `#9EA8BD` | **black** |

**Light variant** (`[data-theme="light"]` and `prefers-color-scheme: light`)

The notch and app screenshots stay black in light mode: it's hardware. Only the page around it
changes.

| Token | Light hex |
|---|---|
| `--bg` | `#F7F5FC` |
| `--bg-grad-top` | `#E4DDFB` |
| `--bg-grad-mid` | `#EFEBFA` |
| `--bg-elev` | `#FFFFFF` |
| `--stroke` | `#15102E` at 10% |
| `--text` | `#15102E` |
| `--text-2` | `#4E4867` |
| `--text-3` | `#736D8C` |
| `--orby-orange` (button fill) | `#C05537`, with `--on-orange` = `#FFFFFF` (4.6:1) |
| `--focus` | `#6B46D9` |
| Phase colors as **text** on light | thinking `#6B46D9`, working `#1F5FD1`, attention `#A85700`, done `#16803F`, error `#C82E2E` |

Phase colors used as fills (orb glow, dots) keep their dark-mode hex in light mode. Run every
text/background pair through a contrast checker before handoff; target 4.5:1 for body text, 3:1
for large text and UI outlines.

### 5.2 Type (Google Fonts)

| Role | Font | Weights | Notes |
|---|---|---|---|
| Display (H1, H2, stats) | **Inter Tight** | 700, 800 | Tracking −3% at H1, −2% at H2. Close to SF Pro, which the app and carousel use, so the screenshots and headlines feel like one product. |
| Body, UI | **Inter** | 400, 500, 600 | Tracking 0. `font-feature-settings: "ss01", "cv11"` for a rounder a. |
| Code, keys, status line | **JetBrains Mono** | 400, 500 | Commands, file names, `⌘Y` key caps, the hero notch line. |

Scale (desktop / mobile, px, line-height):

| Style | Desktop | Mobile |
|---|---|---|
| H1 | 88 / 0.95 | 48 / 1.0 |
| H2 | 56 / 1.05 | 34 / 1.1 |
| H3 | 24 / 1.25 | 20 / 1.3 |
| Body L (hero sub) | 21 / 1.5 | 18 / 1.5 |
| Body | 17 / 1.6 | 16 / 1.6 |
| Caption / eyebrow | 13 / 1.4, 600, uppercase, tracking +8% | 12 / 1.4 |
| Mono | 15 / 1.5 | 13 / 1.5 |

Max line length for body: 64 characters.

### 5.3 Spacing, radius, elevation

- **Spacing scale (4 px base):** 4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 160.
  Section vertical padding 128 desktop / 64 mobile. Card padding 24 / 16.
- **Radius:**
  - 6: key caps (`⌘Y`), small chips
  - 12: cards inside the notch, screenshots
  - 20: feature cards, FAQ items
  - 28: the expanded notch panel's bottom corners
  - 999: buttons and pills (the app's buttons are capsules)
- **Elevation:** no drop shadows on dark. Separate with `--stroke` borders and background steps.
  The only glow on the page is the orb's phase glow. In light mode, cards may use
  `0 1px 2px rgba(21,16,46,.06), 0 8px 24px rgba(21,16,46,.06)`.
- **Buttons:**
  - Primary: `--orby-orange` fill, `--on-orange` label in Inter 600 at 16 px, 48 px tall, 24 px
    side padding, pill. In light mode the fill is `#C05537` with a white label (4.6:1).
  - Secondary: transparent, 1 px `--stroke`, `--text` label.
  - Hover lightens 8%, press darkens 8%. 150 ms ease-out. Minimum target 44 × 44.

### 5.4 Notch and MacBook framing motif

- **The notch shape** comes from `NotchShape` in `Theme.swift`: concave flares at the two top
  corners (the shape curves *outward* into the top edge) and rounded bottom corners. Use top flare
  radius 8 px and bottom radius 16 px collapsed, 28 px expanded.
- **Hero:** the top 24 px of the viewport is a thin MacBook bezel (`#000000`, with a 1 px
  `#FFFFFF` 8% inner highlight along its bottom edge), and the notch hangs from it, centered,
  starting at 200 × 32 px. The notch grows downward and sideways into panels (one line → card).
  Width and height animate with a spring: stiffness 300, damping 30 (≈ 350 ms, slight settle).
- **Section openers:** each H2 section starts with a small 120 × 20 px notch tab hanging from a
  1 px top divider, holding the section's eyebrow text. It's the one repeating ornament; don't add
  others.
- **Screenshots:** always shown hanging from a notch, on black, with the 28 px bottom radius.
  Never float app UI on a gradient without its notch.
- **Final CTA** uses a smaller notch (160 × 28 px) with Orby in done.

---

## 6. Responsive notes

### 6.1 Desktop, 1440 px

- Grid: 12 columns, 1200 px content max width, 24 px gutters, centered (120 px side margins).
- **Hero:** full width bezel and notch. Orby at **240 px** diameter in the notch (`r = 120`),
  canvas 480 px. H1 and subcopy centered below, max 760 px wide. Pinned for 220 vh (section 4.4);
  status-line captions sit to the right of the notch in columns 9–12.
- **States (3.2):** block A is a 4 + 3 grid of tiles (orb 96 px). Block B is 11 small tiles in one
  row of 6 and one of 5 (orb 56 px).
- **Approvals (3.3):** copy in columns 1–5, live card in 6–12. Sub-points as 3 columns below.
- **Agents (3.4):** 8 orbs in one row (72 px each), table below at 8 columns wide, centered.
- **Usage (3.5) and Sounds (3.6):** copy 1–5, visual 7–12; Sounds board is a 4 + 3 grid of
  buttons.
- **Privacy (3.7):** three stat tiles in a row, body text in columns 3–10.
- **FAQ:** single column, 8 columns wide, centered.
- Nav height 64 px.

### 6.2 Mobile, 390 px

- Grid: 4 columns, 16 px side gutters, 16 px column gutters. No horizontal page scroll at any
  point; nothing wider than 358 px.
- **Hero:** notch 160 × 28 px, Orby at **144 px** (`r = 72`). H1 at 48 px, left-aligned. CTAs
  stack full width, primary first. No scroll pin: the choreography autoplays once in view (4.4).
  The permission card in the sequence is shown at full content width with buttons in two rows
  (Deny + Allow, then Always allow).
- **States:** block A as 2 columns (orb 80 px), last tile spans both. Block B as 3 columns (orb
  48 px), labels under each. Tiles play on tap, not on scroll.
- **Approvals:** card first, copy below. Sub-points stack, screenshot above each text.
- **Agents:** orbs in a 4 × 2 grid (56 px). The table becomes a list: agent name bold, capabilities
  on the next line.
- **Sounds:** one button per row, full width, 48 px tall.
- **Privacy:** stat tiles stack.
- **Nav:** wordmark + **Download** button only; links move into a menu button (44 × 44 target).
- **Pointer-following eyes** are off on touch. Instead, the hero orb looks at the last tap
  position for 1500 ms.
- Keep total mobile page weight under 1 MB on first load; lazy-load screenshots below the hero.

---

## 7. Assets list for the designer

| Asset | Use |
|---|---|
| `docs/design/AppIcon-1024.png` | Favicon, OG image base, footer |
| `docs/screenshots/expanded-permission.png` | Approvals, hero choreography reference |
| `docs/screenshots/expanded-question-multi.png`, `expanded-plan.png`, `expanded-edit.png` | Approvals sub-points |
| `docs/screenshots/expanded-sessions.png` | Agents section |
| `docs/screenshots/expanded-usage.png` | Usage |
| `docs/screenshots/collapsed-thinking.png`, `collapsed-working.png`, `collapsed-attention.png` | Collapsed notch reference for the hero |
| `docs/screenshots/mascots-1.png` … `mascots-3.png` | Every orb pose with agent badges |
| `docs/marketing/ig-carousel/*.png` | Tone, type weight and background gradient reference |

Re-render screenshots at 2× with `.build/debug/Orby --render-previews docs/screenshots` if a size
is missing.

---

## 8. To confirm before launch

These affect copy on the page. Flagged, not decided here:

1. **License.** The repo has no LICENSE file, so the page says "View on GitHub" and never "open
   source". Change the copy if a license is added.
2. **Repo visibility.** The GitHub CTA assumes `github.com/ALIFKHIJANAH/orby` is public.
3. **Download hosting.** The primary CTA needs a stable URL to the latest DMG (e.g. a GitHub
   Releases `latest/download` link). `scripts/make-dmg.sh` builds `Orby-<version>.dmg`.
4. **Signing.** Developer ID signing and notarization are still on the roadmap. If the DMG ships
   unsigned, add a FAQ item: "macOS says it can't check Orby for malware" → right-click the app and
   choose Open the first time.
5. **Agent list.** The page lists exactly the eight agents in the README. Update 3.1's eyebrow and
   3.4 together when that list changes.
