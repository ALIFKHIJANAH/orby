# Alt A: Pixel Arcade

pen.dev frame: `Orby Website - Alt A - Pixel Arcade` (node `D2OIb`) in `~/Documents/Orby.pen`, at x=0, y=40000, 1440 × ~10,900.

**Direction.** A retro 8-bit arcade with a CRT-dark background (`#0A0718` with 4 px scanlines and pixel stars). Orby is drawn as real pixel art on a 32 × 32 grid. The page is framed like a game: the bezel works as a HUD (1UP FREE · HI-SCORE ~2 MB · AGENTS 08), the mascot states are a character-select screen, the tool poses are a sprite sheet, and the sounds are an arcade sound board.

## System

- Type: Press Start 2P for headlines and buttons (purple `#4B2BA8` hard drop shadow), Silkscreen for labels, VT323 for motion notes and status lines, IBM Plex Sans for body text, and JetBrains Mono for commands and key caps.
- Color: the brief's palette, hard-coded. Phase colors appear only for state (glow rings, tile borders, meters). Orange `#DF714C` is used only for the primary CTA and the wordmark.
- Effects: no blur and no rounded corners. Panels use 2–4 px borders and hard offset shadows (blur 0). Notches have stepped pixel corners.
- Sprites: generated from the `AgentOrb` numbers. r = 8 cells, eyes 0.28r × 0.56r at ±0.3r, and gaze offsets of 0.42r / 0.38r. The phase glow is a 2-step checker dither. The lower-right shadow and the upper-left rim light are one cell each. Each color is one path, so a sprite is 4–11 nodes.

## Sections

1. Nav
2. Hero: pixel notch with a 384 px Orby in the thinking key pose, notch status line, and six motion callouts
3. How it works: a six-keyframe film strip of the scroll choreography (4.4)
4. Meet Orby: character select with 8 state tiles, each with keyframes A and B, a glow meter, loop length and fps; then an 11-tool sprite sheet with loop timings
5. Approvals: rebuilt permission card, ⌘Y / ⌘N key caps, three screenshot "cartridges"
6. Agents: 8-player roster (hovered Codex is working, its neighbours chat), a "move list" capability table, Jump back, and the sessions screenshot
7. Usage: power-meter panel and a pixel 7-day stacked token chart
8. Sounds: sound board with 7 arcade buttons, each with a piano roll drawn from the 4.6 note tables, plus a now-playing screen and the quiet list
9. Privacy: scoreboard (~2 MB / 0 / 0) and a network-calls log (2 calls, both off by default)
10. FAQ: accordion with 9 items, the first open
11. Final CTA: small notch with Orby in done
12. Footer with the dozing-orb easter egg

## Open points

- The ⌘ glyph isn't in Press Start 2P, so it falls back to another font in the Approvals H2. For the build, either set the key in JetBrains Mono inline or use the key-cap chips.
- Example values in the meters and chart (82%, 64%, 38%, daily blocks) are placeholders, not product claims.
