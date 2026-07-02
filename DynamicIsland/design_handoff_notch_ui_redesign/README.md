# Handoff: VibeIsland Notch UI Redesign

## Overview
A unified dark visual system for every VibeIsland notch surface (Home, Media, Agents, Stats, Clipboard, Color picker, Timer — tab + popover, Weather, Shelf, Calendar — week + month). The redesign fixes the core problem — each tab looking like a different app — by giving every surface the same ink-and-hairline card language, the same mono-label rule, one accent color, and monochrome data visualization.

## About the Design Files
The bundled file (`VibeIsland Redesign.dc.html`) is a **design reference built in HTML** — a static, annotated mockup board showing the intended look of every surface side by side. It is **not production code to copy directly**. VibeIsland is a native **macOS SwiftUI app** (see the existing `DynamicIsland/components/Notch/*.swift` and `DynamicIsland/components/Timer/TimerPopover.swift` files). The task is to **recreate this visual language natively in SwiftUI**, modifying the existing view files in place — reusing the app's existing state/managers (`TimerManager`, `SystemTimerBridge`, agent session sources, etc.) — not to embed a WebView or ship HTML.

## Fidelity
**High-fidelity.** Colors, type sizes/weights, spacing, corner radii, and the mono-label rule below should be treated as final and recreated pixel-precisely with SwiftUI equivalents (matching values, not exact pixels, since SwiftUI/AppKit renders natively). Copy shown (e.g. "refactor auth flow", "Borderline — Tame Impala") is placeholder — wire to real data.

## The system (apply identically to every surface)

**Fonts**
- Voice / titles / body: **Geist** (SwiftUI: use as a custom font via `Font.custom("Geist-...", size:)`; weights 400/500/600/700 needed. If Geist isn't licensed for bundling, the closest system fallback is `.system(size:, weight:, design: .default)`).
- All technical/numeric values (times, percentages, durations, hex codes, filenames, session status, hex/RGB/HSL): **Geist Mono** (`Font.custom("GeistMono-...", ...)`, fallback `.system(..., design: .monospaced)`). This mono-for-data / sans-for-voice split is the single rule that ties every tab together — apply it even to values not explicitly called out below.

**Surface ladder** (dark ink ramp, all surfaces sit on this)
- `#000000` — the notch panel itself (Color.black)
- `#0a0a0a` — canvas background (mockup-board only, not app UI)
- `#151515` / `#141414` — card fill inside a panel
- `#1e1e1e` — raised/hover fill
- Hairlines: white at 6–9% opacity (`Color.white.opacity(0.06–0.09)`), 1pt, used as `border` on every card — never a solid gray border.

**Accent**
- One accent, default `#D97742` (warm Claude-orange). Used sparingly: active/selected states, "today" in calendar, timer ring, agent icon, primary call-to-action fills. Never decorative.
- Status colors (not the brand accent, semantic only): success/running `#3FB27F` green, waiting/needs-permission `#E0A83E` amber, destructive `#E5645F` red, secondary link/info `#6EA8F5` blue.

**Card grammar** ("every card opens the same way")
- Rounded rect, radius 10–16pt depending on size, `#141414` or `#151515` fill, 1pt hairline border.
- First line inside is a mono, uppercase, letter-spaced (~0.12–0.16em) label in `#6E6E6E`–`#8A8A8A` — e.g. "RUNNING", "NEEDS PERMISSION", "CPU", "Recent · 30". This is the repeated signature — every card, every tab, opens with this label before content.

**Notch panel chrome** (applies to every full tab surface: Home, Media, Agents, Stats, Weather, Shelf, Calendar)
- Fixed frame: **720pt wide × 400pt tall** (uniform across every tab — this was an explicit fix in this round; previously each tab sized itself independently, which read as inconsistent).
- Corner radius: `4pt` top corners (flush against the physical notch), `24pt` bottom corners.
- A small camera-cutout dot centered at the top (5×5pt, `#0F0F0F` fill with a 1pt inset stroke `rgba(255,255,255,.12)`) — cosmetic, mirrors the physical camera housing.
- 46pt-tall header row: a pill-shaped tab indicator on the left (`rgba(255,255,255,.09)` fill, 100pt corner radius, icon + label in white), auxiliary icons/actions right-aligned, and on the far right a battery %/icon cluster (only shown on Home/Media — omit elsewhere unless useful).
- Content sits inside the frame below the header; if a surface's content is shorter than 400pt, leave the remaining space as breathing room rather than stretching content (Home, Media, Timer, Weather, and Shelf are intentionally not "full" — Agents and Calendar-month are the densest and set the height ceiling).

**Data visualization**
- No categorical rainbow colors. Sparklines/line charts are monochrome white/light-gray by default; a value only turns amber/red when it crosses a real threshold (e.g. Memory at 99.5% shown in amber in Stats).

## Screens / Views

### 1. Collapsed notch (idle + live activities)
Purpose: the default, unopened state; shows at-a-glance status without opening the panel.
- Idle: a plain black pill, ~210×34pt, rounded only at the bottom (0 0 18 18), a short light-gray "notch" indicator bar centered.
- Now Playing: black pill, ~38pt tall, album art thumbnail on the left, a 4-bar animated equalizer (accent color) on the right.
- Agent permission: black pill with a sparkle icon + "Allow edit?" label + a pulsing amber dot — signals the agent needs a decision without opening Home.
- Timer: black pill with a timer icon + mono countdown (e.g. "12:45").
All four share the same black fill, bottom-only rounding, and content padding — only width/content differs per activity.

### 2. Home (default open panel)
Purpose: landing view when the notch opens — media + agent status at a glance, one tap from either detail view.
- 720×400 frame, header row: Home pill (active/white) + Inbox/Timer/Sparkles/Calendar icon buttons + spacer + battery cluster + settings gear.
- Body: two-column grid, ~14pt gap. Left = compact media card (album thumbnail w/ small green "now playing" glyph badge, title + artist, thin progress bar with mono elapsed/remaining time, shuffle/prev/playPause/next/repeat row, play/pause as a filled white circle). Right = compact agents card (mono "AGENTS" eyebrow + usage chips top-right, then a stacked list of session rows — each a colored status dot/spinner, title, mono status line, and a contextual icon; a "needs permission" row additionally shows inline Allow (green fill) / Deny (red outline) buttons).

### 3. Media player (expanded)
Purpose: full-screen (full-panel) playback controls, reached from Home.
- Same 720×400 frame/header (Home pill only, no other icon buttons, battery cluster right).
- Large 118×118pt album art (rounded 16pt) with a green "now playing" glyph badge bottom-right, "NOW PLAYING" mono eyebrow, large 30px track title, artist/album line, a full-width scrubber (elapsed/remaining mono labels flanking a white-fill progress bar with a round white handle), and a centered transport row (shuffle, prev, large white circular play/pause with black glyph, next, repeat-accent).

### 4. Agents
Purpose: monitor and act on Claude Code sessions running in the terminal.
- Main 720×400 panel: header = Agents pill (accent sparkle icon) + two mono usage chips (5h/7d % — 7d turns amber when high).
- Body: vertical list of session rows, each a card (`#141414`, 12pt radius):
  - **Running**: spinner ring (green), title, mono "running · editing N files · Nm" in green, a "jump to terminal" corner-arrow icon.
  - **Needs permission**: pulsing amber dot, title, mono amber status + the requested command, inline Allow (green, filled, black text) / Deny (red outline) buttons below.
  - **Question**: question-mark icon (accent), title, mono gray prompt text, then a vertical list of numbered option rows (circular numeral badge + label) the user can pick.
- Below the main panel, two supplementary "Other states" cards side by side: **not set up** (wrench icon, "Set up Claude Code" + copy + accent "Install hooks" pill button) and **idle** (moon icon, "No active sessions" + a mono `$ claude` hint).

### 5. System stats
Purpose: live CPU/Memory/GPU/Network/Disk monitor.
- Same 720×400 frame; header = "System" pill + pulsing-green "Live" indicator + right-aligned Pause/Clear text buttons (outlined, no fill).
- Top row: 3 equal cards (CPU, Memory, GPU) — icon + mono uppercase label, large 26px numeral + smaller "%" suffix, a monochrome area-sparkline below (white line + soft white-to-transparent gradient fill; switches to amber when the metric is in a warning state, as shown for Memory at 99.5%).
- Bottom row: 2 equal wide cards (Network, Disk) — icon + label + right-aligned mono up/down throughput, full-width dual-line chart (solid white = primary direction, dimmer gray = secondary).

### 6. Clipboard & Color picker (menu-bar-style popovers)
Purpose: quick-access utilities, not full notch tabs — narrower popover cards.
- **Clipboard**: mono "CLIPBOARD" eyebrow + trash icon, a 2-way segmented control (History/Favorites with mono item counts), a search field, then a list of clipped items — each an icon (image/text/link), title/preview (mono for code/text, blue for URLs), type + size caption, and a relative-time trailing label. Hairline divider between rows.
- **Color picker**: mono "COLOR" eyebrow + accent-colored "+ Pick" pill button. Two columns: left = "Recent · N" swatch list (color chip + mono hex + relative time, most-recent row highlighted with a card background); right = a large color preview swatch + a "Formats" list (HEX/RGB/HSL/HSV/SwiftUI, label left mono-gray, value right mono-white).

### 7. Timer — two forms
Both forms share the same mono-digit fields, preset grammar, and accent countdown ring; only the frame differs.

**Form A — notch tab** (720×400, same chrome as other tabs)
- Header: Timer pill + mono "Set duration" label right-aligned.
- Body: a `#141414` card containing three big mono duration fields (Hours/Minutes/Seconds, 64×52pt each, colon separators), a green "Start" pill + a reset icon button to its right, then a wrapping chip row of saved presets (colored dot + name + mono duration, e.g. green "Focus 25:00", blue "Break 05:00") plus quick-add chips (+1m/+5m/+10m).
- Below, in the "Other states" row: a running state — a circular accent progress ring (SVG stroke-dasharray style; recreate with SwiftUI `Circle().trim` + `.stroke`) with the mono countdown centered inside, session name below, an accent "Running" pill badge, and Pause/Stop circular icon buttons.

**Form B — menu-bar popover** (300pt wide, appears as a standalone popover beside the notch — this matches the existing `TimerPopover.swift`)
- Header: 32×32pt icon tile + "Timer" title + mono status ("Ready"/"Running").
- **Setup state**: a "Custom Timer" card with three compact stepper fields (title above, mono numeral + chevron up/down), a quick-add chip row (+1m/+5m/+10m/+30m + reset icon), mono formatted duration ("10 min"), and an accent-filled "Start Custom Timer" button. Hairline divider. "Presets" list — same colored-dot + name + mono duration rows as Form A, each with a trailing play icon.
- **Running state**: replaces the Custom Timer card with an active card — session name, large 30px mono countdown, an accent progress bar, and side-by-side Pause / Stop buttons (Stop in red). Same preset list below, with the active preset row highlighted (accent-tinted background + checkmark instead of play icon).

### 8. Weather
Purpose: current conditions + 7-day outlook.
- 720×400 frame, header = Weather pill + mono location (pin icon + city name) right-aligned.
- Current block: large monochrome weather glyph, big 56px temp, mono high/low stacked to its right, a divider, condition name + "feels like" caption, then a 2×2 mono detail grid (sunrise/humidity/sunset/wind, each with a dim icon).
- Divider, then a 7-column forecast strip: mono day label (today highlighted lighter), monochrome glyph, mono high°/dim low° pair.

### 9. Shelf
Purpose: quick drag-and-drop file staging + AirDrop-style sharing.
- 720×400 frame, header = Shelf pill + mono item-count/size caption right-aligned.
- Two-column body: a fixed ~150pt "Quick Share" tile (circular share-glyph outline + label + mono subtitle) beside a dashed-border drop zone containing a row of stashed-file cards (thumbnail/type-icon, filename, mono type+size caption) and a "Drop files to stash them here" hint row. The dashed border is intentionally the one place in the whole system a stroke pattern is used — it signals "drop target."

### 10. Calendar — two modes
Both modes share the same 720×400 frame, header pill, and event-row grammar (mono time column, colored 3pt category bar, title + location).

**Mode A — Week**: header adds a Week/Month segmented toggle (Week active, filled white pill) + mono month label. A 7-cell week strip (mono DOW + day numeral; today filled with the accent, weekend numerals dimmed). Divider, then a vertical agenda list of the day's/week's events.

**Mode B — Month**: header adds ‹ mono-month › navigation + the same toggle (Month active). A mono DOW row, then a 5–6 row month grid (each cell: day numeral, dimmed for adjacent months, up to 3 small colored dots beneath for events that day; today's cell is filled with the accent and its dots go dark/translucent for contrast). Divider, then a compact "selected day" summary row (mono date + inline colored-bar event chips + mono event count).

## Interactions & Behavior
- Tab switching in Home's icon row (House/Inbox/Timer/Sparkles/Calendar) swaps the panel body while keeping header chrome — implement as a `TabView`/state-driven `switch` over the existing view enum, not a full remount.
- Agent permission rows: Allow/Deny should call into the existing session-approval API; Question rows submit the selected numbered option.
- Calendar Week/Month segmented toggle is a simple two-state control; persist last-used mode (e.g. via `@AppStorage`).
- Timer popover setup→running transition: use the existing `TimerManager` state (`isTimerActive`) exactly as `TimerPopover.swift` already does — this redesign only restyles it, the state machine is unchanged.
- Stats sparklines should animate smoothly on data updates (existing polling cadence); avoid restyling changes to the animation timing.
- Pulsing dots (amber "needs permission", green "Live"): simple opacity keyframe loop, ~1.6s ease-in-out, 1 ↔ 0.35.

## State Management
No new state is introduced by this redesign — it is a visual-only pass. Reuse:
- `TimerManager.shared` for Timer (both forms).
- Existing agent-session data source for Agents (session list, permission requests, questions).
- Existing `SystemTimerBridge`/system-metrics source for Stats.
- Existing calendar/event store for Calendar (add a `displayMode: .week | .month` preference if one doesn't exist).

## Design Tokens
- Ink ladder: `#000000`, `#0a0a0a`, `#141414`/`#151515`, `#1e1e1e`
- Hairline: white @ 6–9% opacity, 1pt
- Accent: `#D97742` (tweakable — also tested with `#0070F3`, `#3FB27F`, `#7928CA` as alternates)
- Status: success `#3FB27F`, warning `#E0A83E`, danger `#E5645F`, info `#6EA8F5`
- Text: primary `#EDEDED`/`#FAFAFA`, secondary `#9A9A9A`/`#8A8A8A`, tertiary `#6E6E6E`/`#5A5A5A`
- Radii: 4pt (notch-flush top corners) / 24pt (notch bottom corners) / 16pt / 14pt / 12pt / 10pt / 100pt (pills)
- Panel frame: 720 × 400pt fixed, for every full tab surface
- Popover frame: 300pt wide (Timer popover, and match for Clipboard/Color if converting those to true popovers)
- Type: Geist 400/500/600/700 for voice; Geist Mono 400/500 for all technical/numeric values

## Assets
No external image assets — all icons are line-style (Lucide-equivalent; map to closest SF Symbols in SwiftUI, e.g. `sparkles`, `timer`, `cpu`, `memorychip`, `wifi`, `internaldrive`, `cloud.sun`, `tray.and.arrow.down`, `calendar`). Album art and file thumbnails in the mockup are placeholder striped swatches — wire to real artwork/file previews.

## Files
- `VibeIsland Redesign.dc.html` — the full mockup board (all 10 surfaces + both Timer forms + both Calendar modes), included in this handoff folder for reference.
- Existing app files to modify (not included, already in the main codebase):
  - `DynamicIsland/components/Notch/NotchHomeView.swift`
  - `DynamicIsland/components/Notch/NotchAgentsView.swift`
  - `DynamicIsland/components/Notch/NotchTimerView.swift`
  - `DynamicIsland/components/Notch/NotchWeatherView.swift`
  - `DynamicIsland/components/Notch/NotchShelfView.swift`
  - `DynamicIsland/components/Notch/DynamicIslandHeader.swift`
  - `DynamicIsland/components/Tabs/TabSelectionView.swift`
  - `DynamicIsland/components/Timer/TimerPopover.swift`
  - `DynamicIsland/components/Calendar/DynamicIslandCalendar.swift`
