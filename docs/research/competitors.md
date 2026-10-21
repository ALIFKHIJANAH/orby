# Competitor research: AI-agent notch / menu-bar monitors

Researched 2026-10-21. Star counts are from the GitHub API on that date. Other figures come from
the linked pages. Notes on method and limits:

- **Reddit** blocked API access and **Product Hunt** was only partly reachable, so most "loved"
  evidence comes from GitHub issues, HN comments and X posts. Where nothing was found, that is said.
- Labels: **(vendor claim)** means marketing or README text. **UNVERIFIED** means we could not confirm it from a fetched page.
- Many issues are in Chinese. They are translated or paraphrased here, and the link goes to the original.
- "AgentNotch" names several unrelated projects. See [AgentNotch](#agentnotch).

## 1. Overview

| Competitor | Link | Price / license | Agents | Traction signal |
|---|---|---|---|---|
| **Vibe Island** | [vibeisland.app](https://vibeisland.app) · [issues](https://github.com/vibeislandapp/vibe-island) | $19.99 one-time per Mac ("early bird"; $14.99 at launch), 1 yr updates, 2-day trial. Closed source | 30 agents, 20+ terminals (vendor claim). One review says approvals work only for Claude Code, OpenCode and MiMoCode ([vibecoding.app](https://vibecoding.app/blog/vibe-island-review)). The changelog says otherwise, so this is UNVERIFIED | v1.0.53 (2026-10-10). Issue tracker: 158★, about 261 issues. Launch post on X: 277 likes, about 98K views ([link](https://x.com/imedwardluo/status/2039729625157537978)). Repost by @RoundtableSpace: 285 likes, about 76K views. No Product Hunt listing or HN story found |
| **AgentNotch** (Piotr Jura) | [agentnotch.app](https://www.agentnotch.app/) | $9.99 one-time, 1 yr updates, 3-day trial (one page says 14). Closed source | Claude Code, Cursor (including Cloud Agents), Codex, Kimi and OpenCode with approvals. Antigravity and Pi: detection only. Also LM Studio, Cowork, herdr, Hermes | No public traction found. Very active: about 70 releases from v1.0.0 (2026-07-13) to v2.2.3 (2026-10-20) |
| *AgentNotch* (AppGram, different app) | [github](https://github.com/AppGram/agentnotch) | Free, MIT | Claude Code, Codex (via OpenTelemetry) | 220★. Product Hunt: 119 pts, #7 of the day ([PH](https://www.producthunt.com/posts/agentnotch)) |
| **Ping Island** | [erha19/ping-island](https://github.com/erha19/ping-island) | Free, Apache-2.0, Homebrew cask | About 15 agents: Claude Code, Codex CLI/App, Gemini, Antigravity, Qwen, Kimi, OpenCode, Cursor, Copilot, Qoder, CodeBuddy, Hermes, Pi… (README claim). SSH bridge | 1,135★, 126 forks. 76 releases since 2026-04 (v0.32.1 on 2026-09-26). About 34k DMG downloads. 163 of 165 issues closed |
| **Claude Island → Vibe Notch** | [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch) (old `claude-island` URL redirects) | Free, Apache-2.0. Sends anonymous Mixpanel analytics | Claude Code CLI only | 2,527★, 357 forks. Last release v1.3.2 (2026-04-20) and no push since. HN: 3 pts |
| **Notchy** | [notchy.dev](https://notchy.dev) | Free, closed source, donations | A general notch app (about 74 modules). AI usage for Claude Code, Codex, OpenCode, Cursor, Copilot. Permission islands for Claude Code and Codex | Product Hunt: 97 pts, #14 of the day, 15 comments (2026-05-29). Site claims 29,948 installs and 4.32★ from 3,675 ratings (vendor claim) |
| **CodeIsland** (fork of Claude Island) | [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) | Free. GitHub detects no license (UNVERIFIED) | 30+ tools, with approvals for about 12 (README claim). iPhone and Watch companions | 2,509★, 329 forks, 30 releases, pushed 2026-10-11 |
| **Open Vibe Island** | [Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island) | Free, GPL-3.0 | 15 agents, including Claude/Codex desktop apps, Cursor, Gemini, Grok Build. 15+ terminals and IDEs (README claim) | 2,048★, 351 forks, 30 releases, pushed 2026-10-16 |
| **Notchi** | [sk-ruban/notchi](https://github.com/sk-ruban/notchi) | Free, GPL-3.0, Sparkle updates | Claude Code, Codex | 1,042★. HN: 2 pts and 4 pts (2026-03) |
| **CodexBar** (usage only) | [steipete/CodexBar](https://github.com/steipete/CodexBar) | Free, MIT | Codex, Claude Code and "106 providers" (README claim) | 22,685★. Often recommended unprompted on HN |
| **cmux** (agent-aware terminal) | [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux) | Free, GPL (README) | Claude Code, Codex, any agent via `cmux notify` | 28,299★. Show HN: 198 pts / 77 comments ([HN](https://news.ycombinator.com/item?id=47079718)) |
| **Happy** (phone remote) | [slopus/happy](https://github.com/slopus/happy) | Free, MIT, iOS app | Claude Code, Codex (also lists Grok) | 24,239★. Show HN: 30 pts. 1,075 open issues |
| **Omnara** (phone/web remote, YC S25) | [omnara-ai/omnara](https://github.com/omnara-ai/omnara) | Apache-2.0 repo plus SaaS. Free tier "10 sessions/month" (founder on HN). Paid price UNVERIFIED | Claude Code, Codex | 2,948★. Show HN: 310 pts / 168 comments ([HN](https://news.ycombinator.com/item?id=44878650)). Launch HN: 147 pts / 161 comments |

Smaller ones, each with little traction. Star counts are from 2026-10-21. "pts" means HN points.

- **Agent Notifications**, 818★. Cross-platform notifier for Claude, Codex, OpenCode, Gemini and Cursor.
- **ClaudeBar**, 1,551★. Quota menu bar.
- **Notch-Pilot**, 68★. Show HN 9 pts.
- **VibeHub**, 37★. Claude Island fork that adds a menu-bar mode, SSH and OpenCode.
- **Crest** ([crestnotch.app](https://crestnotch.app)). Show HN 6 pts.
- **Fetch** (tryfetch.dev). HN 2 pts.
- **Topsoil**. HN 1 pt.
- **pookify**. HN 3 pts.
- **CCNotify**, 215★.
- **ccnotifs**, 22★. Approve from a macOS notification.
- **Whiplash**. Show HN 2 pts.
- **anshaneja5/claude-island**, 20★. Shows usage in the *iPhone* Dynamic Island.
- **vibepulse**, 212★. ESP32 hardware status display.
- **VibeTunnel**, 4,693★. Terminal in a browser.
- **Agent Sessions**, 906★. History browser.
- **opcode** (formerly Claudia), 22,415★. GUI for Claude Code.

None of these were researched in depth.

## 2. Per competitor

### Vibe Island

The paid market leader, built by a solo developer (Edward Luo / edwluo) who answers issues quickly and in detail. The app is closed source. Its GitHub repo is used only for issues and discussions.

**Loved**
- **One control panel for many parallel sessions.** The founder runs "5-10 conversations" at once and built it so he would stop losing track ([X](https://x.com/imedwardluo/status/2039729625157537978)). A rival maker on HN: "vibe island's amazing as a control panel: approvals, jumping back to the right terminal, lots of sessions" ([HN](https://news.ycombinator.com/item?id=50084818)).
- **Acting on agents from the notch.** "This is the best mac app of 2026. Vibe island lets you see and interact with your agents in the mac notch. I love it so much I'm giving away 10 licenses" ([X @ideabrowser](https://x.com/ideabrowser/status/2039861754981671360)).
- **Sound effects.** "I am obsessed specially with the sound effects" (a testimonial on the vendor site; the original post is UNVERIFIED). An HN user suggests "Protoss WAVs for the agent sound effects" ([HN](https://news.ycombinator.com/item?id=49771659)).
- **Polish.** "东西非常丝滑" ("it's really smooth") ([Discussion #50](https://github.com/vibeislandapp/vibe-island/discussions/50)). "The onboarding experience is incredible" (vendor-site testimonial, UNVERIFIED).
- **Requests ship fast.** Dismissing popups ([#42](https://github.com/vibeislandapp/vibe-island/issues/42)) → optional auto-expand (v1.0.39). Pi support ([#8](https://github.com/vibeislandapp/vibe-island/issues/8)) → v1.0.33. Hermes support ([#57](https://github.com/vibeislandapp/vibe-island/issues/57)) → v1.0.25. Remote sessions ([#60](https://github.com/vibeislandapp/vibe-island/issues/60)) → SSH Remote ([changelog](https://vibeisland.app/changelog/)).

**Complaints**
- **Duplicate permission cards.** "Every permission prompt now raises two identical cards" ([#245](https://github.com/vibeislandapp/vibe-island/issues/245), open). Duplicates are a recurring theme across changelog fixes from v1.0.39 to v1.0.53.
- **Overwrites user config.** It replaced the `statusLine` in `~/.claude/settings.json`, breaking ccstatusline and claude-hud. These are the most-commented issues: [#137](https://github.com/vibeislandapp/vibe-island/issues/137) and [#107](https://github.com/vibeislandapp/vibe-island/issues/107). It also overwrites iTerm2 tab titles ([#181](https://github.com/vibeislandapp/vibe-island/issues/181)).
- **Noise.** The panel pops up "forcibly" and "cannot be turned off" ([#42](https://github.com/vibeislandapp/vibe-island/issues/42)). "Shows + sound for every tool use" in bypass mode ([#114](https://github.com/vibeislandapp/vibe-island/issues/114), later fixed with Silence Rules). Users ask for no sound when subagents finish ([#223](https://github.com/vibeislandapp/vibe-island/issues/223)).
- **Privacy.** The usage helper ran `security dump-keychain`, and the developer called it "bad design on my part" ([#216](https://github.com/vibeislandapp/vibe-island/issues/216)). Third parties claim PostHog/Sentry telemetry with no opt-out (UNVERIFIED).
- **Price.** "$14.99 is a bit expensive" ([Discussion #50](https://github.com/vibeislandapp/vibe-island/discussions/50)). One review says to skip it if Claude Code is your only agent.
- **Other.**
  - The default global `Ctrl+U` shortcut steals the shell's kill-line binding ([#237](https://github.com/vibeislandapp/vibe-island/issues/237)).
  - SSH reconnect loops opened "hundreds of Chrome tabs" ([#160](https://github.com/vibeislandapp/vibe-island/issues/160)).
  - Open requests: multi-monitor ([#10](https://github.com/vibeislandapp/vibe-island/issues/10)), free repositioning ([#180](https://github.com/vibeislandapp/vibe-island/issues/180)), an always-visible usage meter ([#26](https://github.com/vibeislandapp/vibe-island/issues/26)), following macOS Focus ([#124](https://github.com/vibeislandapp/vibe-island/issues/124)).

### AgentNotch

The paid app at agentnotch.app (Piotr Jura) is a different product from AppGram/agentnotch (MIT, 220★, Product Hunt #7). Vibe Island's comparison page rates "AgentNotch" at 2 agents with no approvals, which probably describes the AppGram app.

**Loved:** we found **no real user voices** for agentnotch.app (UNVERIFIED). The vendor emphasises these features, according to its [changelog](https://www.agentnotch.app/changelog):
- Approve or deny with the command and the reason shown.
- Plan limits for several providers with pace, countdown and per-limit bars (v1.1.3, v1.3.1, v2.1.5).
- Jump to the exact pane or thread, including the Codex desktop app (v1.1.6, v1.4.8).
- Low idle CPU ("about 25% less idle CPU", v1.5.5).
- Grouping by project and worktree (v2.1.0).

**Complaints:** none from users were found. The changelog points to weak spots:
- Licensing bugs at launch (v1.1.1–1.1.2).
- Approval bugs (v1.2.2, v2.2.3).
- Sessions disappearing (v1.4.9).

### Ping Island

The most active open-source competitor. The user base is largely Chinese-speaking. Releases ship several times a week, and nearly every issue gets closed.

**Loved**
- **Jumps to Claude Desktop.** "Of the similar products I've used, only this one can jump to the Claude Code desktop app" ([#213](https://github.com/erha19/ping-island/issues/213), titled "产品很棒" ("great product")).
- **Agent support added on request.** Kimi was added ([#141](https://github.com/erha19/ping-island/issues/141)) and Qoder CN too ([#256](https://github.com/erha19/ping-island/issues/256)). The Codex App is confirmed to work ([#143](https://github.com/erha19/ping-island/issues/143#issuecomment-4398057255)).
- **Notch width setting**, shipped within days of the request ([#213](https://github.com/erha19/ping-island/issues/213#issuecomment-4588933326)).
- **Session-aware keep-awake** (Off / Auto / Always on), contributed by the community in v0.30.0 ([#306](https://github.com/erha19/ping-island/issues/306#issuecomment-5602901986)).
- **Zombie-session cleanup.** A liveness scan removes sessions whose process has exited. This has the most reactions of any issue ([#74](https://github.com/erha19/ping-island/issues/74)).
- Per-session auto-approve, a detachable floating mascot, themes, custom sounds (README claim).

**Complaints**
- **Settings freezes the app** for several seconds, still present after the claimed fix ([#167](https://github.com/erha19/ping-island/issues/167), 7 comments).
- **Energy use is too high** ([#223](https://github.com/erha19/ping-island/issues/223)).
- **Too much noise.** "Every think step shows a ToolUse prompt" ([#122](https://github.com/erha19/ping-island/issues/122)). Approve buttons appear even where they do nothing ([#234](https://github.com/erha19/ping-island/issues/234#issuecomment-4645526252)).
- **Codex sessions are sometimes not detected** ([#183](https://github.com/erha19/ping-island/issues/183)).
- **SSH problems.** Remote bootstrap creates config directories for every agent ([#249](https://github.com/erha19/ping-island/issues/249)), and connections are unstable ([#95](https://github.com/erha19/ping-island/issues/95)).

### Claude Island / Vibe Notch

This was the original open-source notch app for Claude Code. It is now largely dormant: no push in six months, even though the README says "Actively maintained". Its forks have overtaken it: CodeIsland, VibeHub and possibly Open Vibe Island.

**Loved**
- **Approvals from the notch.** "Super awesome app, I love it… a super unique use of the notch! The alerts work great when Claude needs some approval" ([#1](https://github.com/farouqaldori/vibe-notch/issues/1)). @dotey on X: approve or deny buttons pop out of the notch, "one click, no window switching" ([X](https://x.com/dotey/status/2040850151405707702); engagement not checked).
- **"Finished" notification**, contributed by the community for v1.2 ([#1 comment](https://github.com/farouqaldori/vibe-notch/issues/1#issuecomment-3634952101)).
- **A good base to build on.** "Built CodeIsland on top of your project" ([#64](https://github.com/farouqaldori/vibe-notch/issues/64)).

**Complaints**
- **No sessions detected** with Warp, Terminal or Ghostty. This is the most-commented issue and is still open ([#11](https://github.com/farouqaldori/vibe-notch/issues/11)).
- **App couldn't be quit**, fixed in v1.3 ([#20](https://github.com/farouqaldori/vibe-notch/issues/20)).
- **UI too large on external or ultrawide monitors** ([#41](https://github.com/farouqaldori/vibe-notch/issues/41)). Users want to opt out of the island and use a menu-bar mode instead ([#58](https://github.com/farouqaldori/vibe-notch/issues/58)).
- **Don't edit `~/.claude`**; ship the integration as a Claude Code plugin instead ([#7](https://github.com/farouqaldori/vibe-notch/issues/7), 4 reactions).
- **Wrong state.** The sound plays when a subagent finishes ([#36](https://github.com/farouqaldori/vibe-notch/issues/36)). The status sticks on "Processing…" after a background Bash command ([#98](https://github.com/farouqaldori/vibe-notch/issues/98)). Users ask whether the project is maintained ([#44](https://github.com/farouqaldori/vibe-notch/issues/44)).

### Notchy

Notchy is a free, general-purpose Dynamic Island with about 74 modules. Agent features are one module among many. It is not Adam Lyttle's MIT "Notchy", which is a terminal in the notch. The agent features cover usage tracking and permission islands. On the roadmap, jumping to a running agent is listed as "Building now", so it isn't shipped yet ([roadmap](https://notchy.dev/roadmap/)).

**Loved**

Users mostly praise features that have nothing to do with agents.
- **Polish.** "Surprisingly polished for a free tool" ([PH](https://www.producthunt.com/products/notchy)).
- **All-in-one hub.** "Transformed my entire computer into a control center" ([notchy.dev](https://notchy.dev)). Users like the Apple Reminders integration ([reviews](https://notchy.dev/reviews/)).
- **OpenCode usage tab**, added on request in v1.0.219 ([feedback #67](https://github.com/vishvavariya/notchy-feedback/issues/67)).
- **Approval work driven by feedback** (no user praise found for it):
  - full command shown before approving (v1.0.210)
  - narrower "Always" approvals (v1.0.211)
  - revoking standing approvals (v1.0.134)

  Source: [changelog](https://notchy.dev/changelog/).

**Complaints**
- **Bloat and RAM.** "much bloatware and duplicate options". The maker admits "I haven't done a dedicated memory (RAM) pass" ([#67](https://github.com/vishvavariya/notchy-feedback/issues/67)).
- **Battery and idle-CPU questions**, plus a bug where part of the screen became unclickable ([PH](https://www.producthunt.com/products/notchy)).
- **Notifications stay visible too long** ([reviews](https://notchy.dev/reviews/)).

### CodeIsland

CodeIsland is a fork of Claude Island and is now the open-source app with the most features. It is on par with Claude Island in stars (2,509★). Its README advertises:
- the agent's task checklist as a progress bar, plus Claude's "while you were away" recap
- global shortcuts for approve, deny, skip and jump
- auto-proceed for agents already running in YOLO mode
- quiet hours, mute while the screen is locked, and a "glance dot" completion style
- opt-in **follow-up reminders** for unanswered approvals
- SSH remote hosts
- **push to Bark, ntfy, Slack or Telegram only while you're away** (screen locked, or 5 minutes with no input)
- webhook forwarding
- several Claude/Codex config directories
- iPhone and Watch Dynamic Island companions, and an ESP32 desk buddy

Source: [README](https://github.com/wxtsky/CodeIsland).

**Loved (by demand signals):**
- The most-reacted issues ask for **more agents and keeping up with them**: Antigravity 2 hooks ([#215](https://github.com/wxtsky/CodeIsland/issues/215)), the Codex `config.toml` hook change ([#162](https://github.com/wxtsky/CodeIsland/issues/162)), ZCode ([#245](https://github.com/wxtsky/CodeIsland/issues/245)).
- A community member built an ESP32 hardware buddy ([#178](https://github.com/wxtsky/CodeIsland/issues/178)).
- A user asked for forwarding hook events to another service ([#115](https://github.com/wxtsky/CodeIsland/issues/115)), which shipped as webhook forwarding.

**Complaints**
- **Permission popup renders transparent or black** ([#100](https://github.com/wxtsky/CodeIsland/issues/100), 8 comments).
- **SSH connection failures** ([#190](https://github.com/wxtsky/CodeIsland/issues/190)).
- **Plan-mode questions re-appear after being answered** ([#170](https://github.com/wxtsky/CodeIsland/issues/170)).
- **Codex "always allow" breaks.** It is rejected with "unsupported updatedPermissions" ([#155](https://github.com/wxtsky/CodeIsland/issues/155)).
- **Agent updates break support.** For example, the new Antigravity was not supported ([#189](https://github.com/wxtsky/CodeIsland/issues/189)).

### Open Vibe Island

An open-source (GPL) answer to Vibe Island. It has the broadest jump-back support in the README:
- terminals: Ghostty, cmux, Kaku, Zellij
- IDEs: JetBrains IDEs
- desktop apps: deep link into Codex Desktop threads via `codex://threads/<id>`

Source: [README](https://github.com/Octane0411/open-vibe-island).

**Loved (by demand signals)**
- **Focus the parent IDE for embedded terminals** in VS Code or Obsidian. This is the top-reacted request ([#173](https://github.com/Octane0411/open-vibe-island/issues/173)).
- **SSH remote agents** ([#98](https://github.com/Octane0411/open-vibe-island/issues/98)).
- **Copilot CLI support** ([#308](https://github.com/Octane0411/open-vibe-island/issues/308)).
- **Claude Desktop integration** ([#510](https://github.com/Octane0411/open-vibe-island/issues/510), 7 comments).

**Complaints**
- **Crashes** ([#482](https://github.com/Octane0411/open-vibe-island/issues/482)).
- **High CPU and heat on an M2 Max** ([#553](https://github.com/Octane0411/open-vibe-island/issues/553)).
- **"Serious memory leak"** ([#481](https://github.com/Octane0411/open-vibe-island/issues/481)).
- **New animations feel "less lively than before"** ([#500](https://github.com/Octane0411/open-vibe-island/issues/500)).
- **Stale Cursor indicator** ([#340](https://github.com/Octane0411/open-vibe-island/issues/340)).
- **Wrong cmux tab selected** ([#607](https://github.com/Octane0411/open-vibe-island/issues/607)).

### Notchi

This is the closest notch-native rival in spirit. README features:
- mascots for each state
- one sprite per session
- quota bar and 30-day cost chart
- sounds muted while the terminal is focused
- optional prompt sentiment analysis using your own API key

User voice: "Great work on Notchi — love the concept and the execution" ([#36](https://github.com/sk-ruban/notchi/issues/36)).

Requests:
- auto-hide when no session is running ([#36](https://github.com/sk-ruban/notchi/issues/36))
- SSH/remote Claude ([#33](https://github.com/sk-ruban/notchi/issues/33))
- external-monitor support ([#24](https://github.com/sk-ruban/notchi/issues/24))
- respecting `$CLAUDE_CONFIG_DIR` ([#35](https://github.com/sk-ruban/notchi/issues/35))

### CodexBar (usage only, adjacent)

This is the de facto answer to "how do I see my limits". It has by far the most traction in the space.

**Loved**
- It's the usual recommendation. "Use CodexBar" ([HN](https://news.ycombinator.com/item?id=48965787)).
- It covers more providers than alternatives ([HN](https://news.ycombinator.com/item?id=48476211)).
- It shows "token spend across multiple subscriptions" ([HN](https://news.ycombinator.com/item?id=48928223)).
- It has desktop widgets ([HN](https://news.ycombinator.com/item?id=49596446)).

**Complaints**
- Lag and bloat. "was… since the last 2-3 updates it has become super laggy… BLOATED" ([#1364](https://github.com/steipete/CodexBar/issues/1364), 37 reactions).
- Repeated keychain prompts despite "Always Allow" ([#108](https://github.com/steipete/CodexBar/issues/108)).
- Fear of bans from reusing credentials ([HN](https://news.ycombinator.com/item?id=47071237)).

### cmux (terminal, adjacent)

**Loved**
- It fixes the context-free "Claude is waiting for your input" notification with notification rings and a jump to the latest unread (README claim).
- `cmux notify` works for any agent ([HN](https://news.ycombinator.com/item?id=47080908)).
- The "What's your favorite cmux feature?" issue has 136 reactions ([#469](https://github.com/manaflow-ai/cmux/issues/469)).

**Complaints**
- **The Running / Needs Input indicators are flaky**: false positives and missed waits ([#1027](https://github.com/manaflow-ai/cmux/issues/1027), 44 reactions). This is Orby's core promise.
- Users don't want to switch terminals: "will stick with Ghostty" ([HN](https://news.ycombinator.com/item?id=47080522)).

### Happy and Omnara (phone remote, adjacent)

They show strong demand for **approving while you're away from the desk**.

**Happy: loved**
- E2E encryption: "The lack of E2E encryption was why I didn't chose Omnara" ([HN](https://news.ycombinator.com/item?id=46995532)).
- A self-hostable relay ([HN](https://news.ycombinator.com/item?id=46992608)).
- Live sync across devices ([HN](https://news.ycombinator.com/item?id=46994524)).

**Happy: complaints**
- Doubts about maintenance ([#223](https://github.com/slopus/happy/issues/223), 29 reactions).
- **Stuck Codex permission prompts** ([#302](https://github.com/slopus/happy/issues/302)).
- OpenCode is the top request ([#265](https://github.com/slopus/happy/issues/265), 55 reactions).

**Omnara: loved**
- The UI ([HN](https://news.ycombinator.com/item?id=46992024)).
- Moving a session from local to a cloud sandbox ([HN](https://news.ycombinator.com/item?id=46994669)).

**Omnara: complaints**
- No E2EE: "If you can see the messages… that's a deal breaker" ([HN](https://news.ycombinator.com/item?id=46992325)).

## 3. What keeps coming up

1. **Accurate state matters most.** The most common complaint in every project is a wrong state:
   - duplicate cards ([Vibe Island #245](https://github.com/vibeislandapp/vibe-island/issues/245))
   - stuck "Processing…" ([Vibe Notch #98](https://github.com/farouqaldori/vibe-notch/issues/98))
   - flaky "Needs Input" ([cmux #1027](https://github.com/manaflow-ai/cmux/issues/1027))
   - zombie sessions ([Ping #74](https://github.com/erha19/ping-island/issues/74))
   - sessions not detected ([Vibe Notch #11](https://github.com/farouqaldori/vibe-notch/issues/11), [Ping #183](https://github.com/erha19/ping-island/issues/183))
2. **The most-requested feature is agent coverage.** The top requests and reactions in nearly every project ask for "support agent X", and for keeping up when an agent changes its hook format.
3. **Users punish noise.** Forced popups, a sound on every tool call, and sounds when subagents finish are all reported as problems.
4. **Users punish resource use.** Energy, CPU, heat, RAM and lag complaints appear in Ping, Open Vibe Island, Notchy and CodexBar.
5. **Users want their config left alone.** Overwriting `statusLine` and iTerm titles, and keychain dumps, cost Vibe Island trust.
6. **Remote work is a recurring ask and a recurring source of bugs.** This covers SSH (Vibe Island, Ping, CodeIsland, Notchi, Open Vibe Island) and phone apps (Happy, Omnara).
7. **People get attached to delight features.** Sound effects, mascots and the novelty of the notch itself are what users praise in their own words.

## 4. Gap list for Orby

Ranked by **evidence of demand × fit with Orby**: a native, lightweight, privacy-first app with no
accounts. Demand and fit are each rated H, M or L. Things Orby already has are listed at the end.

| # | Feature people love | Orby today | Demand | Fit | Evidence | Implementation idea |
|---|---|---|---|---|---|---|
| 1 | **More agents** (Gemini CLI, Cursor CLI, OpenCode, Copilot CLI, Pi, Kimi, Qwen) | Claude Code, Codex, Antigravity | H | H | Top requests everywhere: [Happy #265](https://github.com/slopus/happy/issues/265) (55 reactions), [OVI #308](https://github.com/Octane0411/open-vibe-island/issues/308), [VI #8](https://github.com/vibeislandapp/vibe-island/issues/8)/[#57](https://github.com/vibeislandapp/vibe-island/issues/57), [Ping #141](https://github.com/erha19/ping-island/issues/141) | Gemini CLI and Cursor use Claude-style JSON hooks: add a `source` to `HookInstaller` plus a payload decoder. OpenCode and Pi need a small plugin file written by Connect |
| 2 | **Desktop-app agents**: Claude Desktop (Code tab), Codex Desktop, with a precise jump | — (not found in source) | M–H | H | "Only this one can jump to the Claude Code desktop app" ([Ping #213](https://github.com/erha19/ping-island/issues/213)). [OVI #510](https://github.com/Octane0411/open-vibe-island/issues/510). [VI #253](https://github.com/vibeislandapp/vibe-island/issues/253) | Accept hook events with no TTY. Track liveness through the desktop app's process. Jump with `codex://threads/<id>` (as OVI does) or activate Claude.app |
| 3 | **Stay quiet unless needed**: silence rules, quiet hours, macOS Focus, mute while locked, no sound when a subagent finishes | ◐ quiet when the agent's terminal is focused, per-event sound toggles, hide when idle | H | H | [VI #42](https://github.com/vibeislandapp/vibe-island/issues/42), [#114](https://github.com/vibeislandapp/vibe-island/issues/114), [#223](https://github.com/vibeislandapp/vibe-island/issues/223), [#124](https://github.com/vibeislandapp/vibe-island/issues/124). [Vibe Notch #36](https://github.com/farouqaldori/vibe-notch/issues/36). [Ping #122](https://github.com/erha19/ping-island/issues/122) | Skip `SubagentStop` sounds. Add a quiet-hours schedule. Mute on `com.apple.screenIsLocked`. Read Focus through `INFocusStatusCenter` |
| 4 | **Prove it's light**: low idle CPU, energy, RAM | ✅ native, about 2 MB (no published CPU/RAM numbers) | H (as a complaint) | H | [Ping #223](https://github.com/erha19/ping-island/issues/223), [OVI #553](https://github.com/Octane0411/open-vibe-island/issues/553)/[#481](https://github.com/Octane0411/open-vibe-island/issues/481), [CodexBar #1364](https://github.com/steipete/CodexBar/issues/1364) (37 reactions), [Notchy #67](https://github.com/vishvavariya/notchy-feedback/issues/67) | Measure idle CPU and RSS with Instruments, publish them in the README, and pause orb animations while the island is collapsed |
| 5 | **Don't double-prompt alongside other notch apps** | ◐ the README warns about it | H | H | Duplicate cards are Vibe Island's most persistent bug ([#245](https://github.com/vibeislandapp/vibe-island/issues/245)). Users often try several of these apps | On Connect, scan hook configs for `vibe-island-bridge`, `ping-island`, `codeisland` and similar, show a warning, and offer to disable Orby's PermissionRequest hook for that agent |
| 6 | **Push to phone while away** (ntfy, Bark, Telegram), approving still happens on the Mac | — | M–H | M | CodeIsland ships it. Happy (24k★) and Omnara (310-pt Show HN) show demand for away-from-desk approvals. E2EE and privacy are deal-breakers ([HN](https://news.ycombinator.com/item?id=46992325)) | Opt-in ntfy or Bark URL. Send only after 5 minutes idle or when the screen is locked. Redact commands. No relay server |
| 7 | **SSH remote sessions** | — (on the roadmap) | M–H | M | [VI #60](https://github.com/vibeislandapp/vibe-island/issues/60), [OVI #98](https://github.com/Octane0411/open-vibe-island/issues/98), [Notchi #33](https://github.com/sk-ruban/notchi/issues/33). Stability is a common complaint: [Ping #95](https://github.com/erha19/ping-island/issues/95), [VI #160](https://github.com/vibeislandapp/vibe-island/issues/160), [CodeIsland #190](https://github.com/wxtsky/CodeIsland/issues/190) | `orby remote add host`: scp a Linux bridge, add hooks remotely, forward `app.sock` with `ssh -R`. Touch only the config of the agent you pick ([Ping #249](https://github.com/erha19/ping-island/issues/249)) |
| 8 | **Precise jump for Ghostty, Warp, cmux, Zellij, JetBrains** | ◐ iTerm2, Terminal, tmux, Kitty, WezTerm, VS Code-family and Zed are precise. Ghostty and Warp only get app activation | M | H | [OVI #607](https://github.com/Octane0411/open-vibe-island/issues/607), [Vibe Notch #11](https://github.com/farouqaldori/vibe-notch/issues/11) (Ghostty/Warp users). Ghostty is the terminal HN users mention most | cmux has a socket API (OVI uses it). Zellij has `zellij action`. Whether Ghostty and Warp offer a tab-targeting API is UNVERIFIED and needs research |
| 9 | **Task checklist / progress bar** (from TodoWrite) | — | M | H | Vibe Island, AgentNotch and CodeIsland all ship it. No direct user quote found | Parse `TodoWrite` tool input from `PreToolUse` and show done/total on the session row |
| 10 | **Global "jump to the session that needs me" hotkey and session switcher** | ◐ ⌘Y/⌘N only while a request is open | M | H | CodeIsland global approve/deny/skip/jump. Vibe Island switcher. Pitfall: [VI #237](https://github.com/vibeislandapp/vibe-island/issues/237) (Ctrl+U stole kill-line) | Use `HotKeys` to register a configurable jump hotkey, off by default, and never use a bare Ctrl+letter |
| 11 | **Menu-bar-only mode and multi-display** | ◐ menu bar list exists. One screen (built-in or main) | M | M | [Vibe Notch #41](https://github.com/farouqaldori/vibe-notch/issues/41)/[#58](https://github.com/farouqaldori/vibe-notch/issues/58), [VI #10](https://github.com/vibeislandapp/vibe-island/issues/10)/[#180](https://github.com/vibeislandapp/vibe-island/issues/180), [Notchi #24](https://github.com/sk-ruban/notchi/issues/24) | Add an "Island: off" setting so only the menu bar extra is shown. Add an option to show a panel on every `NSScreen` |
| 12 | **Usage alerts and widget** | ◐ Codex and Claude limits, 85% line, 7-day chart | M | M | CodexBar (22.7k★) is loved for this. Users ask for an always-visible meter ([VI #26](https://github.com/vibeislandapp/vibe-island/issues/26)). It's a crowded, commodity space | Send a notification at 80% and 95% plus a pace warning. Optionally add a WidgetKit widget. Avoid keychain prompts ([CodexBar #108](https://github.com/steipete/CodexBar/issues/108)) |
| 13 | **Several Claude accounts / config dirs** | ◐ reads the `CLAUDE_CONFIG_DIR` environment variable only | L–M | H | [Notchi #35](https://github.com/sk-ruban/notchi/issues/35). CodeIsland supports extra config dirs | In Integrations, let users list extra config dirs. Connect installs hooks into each one |
| 14 | **Auto-update and Homebrew cask** | — (on the roadmap) | M | H | Every serious rival ships Sparkle and/or a cask. A user asked for an RSS feed of updates ([VI #257](https://github.com/vibeislandapp/vibe-island/issues/257)) | Sparkle with an appcast on GitHub Releases, plus a `homebrew-cask` PR after notarization |
| 15 | **Keep the Mac awake while agents work** | — | L–M | H | Ping v0.30.0, community PR ([#306](https://github.com/erha19/ping-island/issues/306)) | Hold an `IOPMAssertion` while any session is working. Setting: Off / Auto |
| 16 | **Follow-up reminders** for unanswered approvals | — | L | H | CodeIsland (README) | Play the chime again or bounce the orb after N minutes of no answer |
| 17 | **Install as a Claude Code plugin instead of editing settings.json** | ◐ additive edits with backups. Orby never touches `statusLine` | L–M | M | [Vibe Notch #7](https://github.com/farouqaldori/vibe-notch/issues/7) (4 reactions). The VI statusLine backlash ([#137](https://github.com/vibeislandapp/vibe-island/issues/137)) | Publish a plugin with a `hooks.json` that points to `~/.orby/bin/orby-bridge`. Keep settings.json as the fallback |
| 18 | **Localization** (Chinese first) | — | M | M | Most Ping, CodeIsland, Vibe Island and OVI issues are in Chinese. Vibe Island has 11 languages | Use a String Catalog (`.xcstrings`), add zh-Hans first |
| 19 | **Webhook forwarding of events** | — | L | M | [CodeIsland #115](https://github.com/wxtsky/CodeIsland/issues/115) | Opt-in POST of the event envelope to a configured URL |
| 20 | **iPhone / Watch companion, hardware buddy** | — | L–M | L | CodeIsland, anshaneja5/claude-island, [CodeIsland #178](https://github.com/wxtsky/CodeIsland/issues/178), vibepulse | Out of scope for now. Row #6 (push) covers most of the need |

### Loved features Orby already has (keep investing)

| Feature | Evidence it's loved | Orby |
|---|---|---|
| Approve, deny or always-allow from the notch | [Vibe Notch #1](https://github.com/farouqaldori/vibe-notch/issues/1), [@dotey](https://x.com/dotey/status/2040850151405707702), [@ideabrowser](https://x.com/ideabrowser/status/2039861754981671360) | ✅ ⌘Y/⌘N, Always allow, hand back to terminal |
| Answer questions, plan review | Feature parity with VI, AgentNotch and CodeIsland. Plan-mode bugs at rivals ([CodeIsland #170](https://github.com/wxtsky/CodeIsland/issues/170)) | ✅ |
| Jump to the right terminal, or the parent IDE for embedded terminals | [HN](https://news.ycombinator.com/item?id=50084818), [OVI #173](https://github.com/Octane0411/open-vibe-island/issues/173) (top request) | ✅ VS Code, Cursor, Windsurf, Zed folder window. iTerm2, Terminal, tmux, Kitty, WezTerm panes |
| Cleanup of dead and zombie sessions | [Ping #74](https://github.com/erha19/ping-island/issues/74) | ✅ dead-PID detection plus TTL |
| Clears the card when answered in the terminal | Duplicate and stale card complaints ([VI #245](https://github.com/vibeislandapp/vibe-island/issues/245)) | ✅ |
| Hide when idle, notch width setting | [Notchi #36](https://github.com/sk-ruban/notchi/issues/36), [Ping #213](https://github.com/erha19/ping-island/issues/213) | ✅ |
| Quiet when you're already looking at the terminal | Noise complaints (section 3) | ✅ |
| Sounds (8-bit, custom folder), mascot | "obsessed with the sound effects" (VI testimonial). Mascots in Notchi and AgentNotch | ✅ AgentOrb, synthesized 8-bit, custom sounds |
| Thinking state with a reasoning snippet | Vibe Island has it. AgentNotch doesn't | ✅ |
| No telemetry, no accounts, no config clobbering | VI keychain and statusLine backlash ([#216](https://github.com/vibeislandapp/vibe-island/issues/216), [#137](https://github.com/vibeislandapp/vibe-island/issues/137)). Vibe Notch has Mixpanel | ✅ the only network call is the opt-in Claude limit request. Hook edits are additive and backed up |
| Free | VI price complaint ([Discussion #50](https://github.com/vibeislandapp/vibe-island/discussions/50)) | ✅ |
