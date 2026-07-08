<div align="center">

# VibeIsland

**A command center for your MacBook notch.**

Media, AI coding agents, system status, and everyday utilities stay visible
without taking over your desktop.

`macOS 14.6+` · `SwiftUI` · `GPL-3.0`

</div>

![VibeIsland home view with media controls and an AI agent permission prompt](docs/images/vibeisland-home.png)

## What VibeIsland does

- **AI agent command center** — follow active sessions, see which agents need
  input, answer questions, approve or deny permission requests, and jump back to
  the originating terminal.
- **Usage at a glance** — inspect provider rate limits, token usage, cache
  activity, cost, and active time.
- **Media and live activities** — control playback and surface timely status
  around the notch.
- **Productivity tools** — use the calendar, timer, weather view, file shelf,
  downloads, shortcuts, and notifications without opening another window.
- **Native system HUDs** — replace selected macOS overlays with notch-aware
  volume, brightness, battery, input-source, and device indicators.
- **Customizable behavior** — tune layout, animations, hover behavior,
  auto-expansion, sounds, and individual modules from Settings.

## AI agents, without the context switching

VibeIsland provides one-click hook/plugin setup for **Claude Code** (and its
hook-compatible forks — Qoder, Qwen Code, Factory, CodeBuddy, Kimi), **Codex**,
**Gemini CLI**, **Antigravity**, **OpenCode**, and **Cursor**. Sessions can
remain compact while they run, then surface automatically — with a red halo and
a sound — when an agent asks a question or requests permission.

![AI agent sessions and combined usage summary](docs/images/agent-usage.png)

### Respond from the notch

| Questions | Permission requests |
| --- | --- |
| ![Answer an agent question from VibeIsland](docs/images/agent-question.png) | ![Approve or deny an agent permission request](docs/images/agent-permission.png) |

### Track provider usage

![Agent sessions and provider usage details](docs/images/agent-provider-usage.png)

VibeIsland's usage panel separates agent session monitoring from provider
usage, so tools that do not expose live hooks can still appear as usage cards.

| Provider / tool | Live sessions | Status states | In-notch actions | Usage data |
| --- | --- | --- | --- | --- |
| Claude Code (+ Qoder, Qwen Code, Factory, CodeBuddy, Kimi) | Yes | idle · thinking · executing · compacting · input-needed · complete | Answer questions, approve/deny permissions, jump-back | Tokens, cache, active time, cost, and Claude 5h / 7d rate-limit windows |
| Codex | Yes | thinking · executing · input-needed · complete | Approve/deny permissions; questions are shown read-only (answer in the terminal); jump-back | Tokens, cache, reasoning, active time, cost, and 5h / weekly windows |
| OpenCode | Yes | thinking · executing · input-needed · complete | Answer questions, approve/deny permissions, jump-back | Tokens, cache, active time, cost, and quota windows (sign-in) |
| Antigravity | Yes | executing · complete | Session status, jump-back | Tokens, cache, active time, cost, and shared quota windows (sign-in) |
| Gemini CLI | Yes | thinking · complete | Session status, jump-back | Tokens, cache, reasoning, active time, and cost |
| Cursor | Yes | thinking · executing · input-needed · complete | Input-needed halo + sound when it waits on you; jump-back to approve in Cursor (its own allowlist governs the actual decision) | Token and cost export from cursor.com |
| GitHub Copilot | Usage only | — | — | Token, cache, active time, and cost where local usage data is available |

Questions and permission requests you can answer in the notch use each tool's
blocking hook; Codex questions and Cursor commands are surfaced (halo, text,
jump-back) but are answered in the terminal, because those tools provide no
channel to send the answer back.

Jump-back uses the terminal metadata captured by each hook and falls back to
opening the owning app or workspace when exact pane targeting is not available.

| Terminal / host | Jump-back behavior |
| --- | --- |
| iTerm, Terminal.app, Ghostty | Activates the app and targets the matching session, tab, TTY, or title when possible |
| Warp | Activates Warp and attempts precise tab targeting using Warp's live pane state |
| WezTerm, Kaku | Uses the app CLI to focus the matching pane by pane id, title, or working directory |
| tmux, Zellij, cmux | Targets the recorded pane or surface, then activates the parent terminal |
| VS Code, VS Code Insiders, Cursor, Windsurf, Trae | Reopens the recorded workspace in the matching editor family app |
| JetBrains IDEs | Opens the recorded project in IntelliJ IDEA, WebStorm, PyCharm, GoLand, CLion, RubyMine, PhpStorm, Rider, or RustRover |
| Codex.app | Opens the recorded Codex thread directly when a thread id is available |

## More than an agent monitor

The same interface also hosts the tools that are useful throughout the day.

| File shelf and AirDrop | Calendar |
| --- | --- |
| ![VibeIsland file shelf and AirDrop view](docs/images/file-shelf.png) | ![VibeIsland calendar view](docs/images/calendar.png) |
| **Weather** | **Timer** |
| ![VibeIsland weather view](docs/images/weather.png) | ![VibeIsland timer view](docs/images/timer.png) |

## Requirements

- A Mac running macOS 14.6 or later
- Xcode 16 or later to build from source

## Build from source

```bash
git clone https://github.com/Zaaacqwq/vibeIsland.git
cd vibeIsland
open DynamicIsland.xcodeproj
```

In Xcode, select the **DynamicIsland** scheme and run the app. You can also build
from the command line:

```bash
xcodebuild -project DynamicIsland.xcodeproj \
  -scheme DynamicIsland \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

The agent-monitoring engine is a local Swift package in
`Packages/OpenIslandEngine`. Run its tests with:

```bash
cd Packages/OpenIslandEngine
swift test
```

## Enable agent monitoring

1. Open **Settings → Developer → Agents**.
2. Turn on **Enable agent monitoring**.
3. Install the integration for each coding agent you use.
4. Start a new agent session. It will appear in the notch automatically.

The installers add VibeIsland-namespaced hooks or plugins to each tool's local
configuration. Integrations fail open: if VibeIsland is not running, they do not
block the coding agent.

## Credits and license

VibeIsland is an independent project built on the open-source
[Atoll](https://github.com/Ebullioscopic/Atoll) notch app.

The project is licensed under the **GNU General Public License v3.0**. See
[LICENSE](LICENSE) for the license and [NOTICE](NOTICE) for complete attribution.
