# VibeIsland

A native macOS app that turns the MacBook notch into a command surface — media
controls, system insight, quick utilities, **and live monitoring of your AI
coding agents** (Claude Code sessions, permission prompts, and one-click
jump-back to the terminal).

> VibeIsland is an independent project. It builds on the open-source
> [Atoll](https://github.com/Ebullioscopic/Atoll) notch app and embeds the
> agent-monitoring engine from
> [Open Island](https://github.com/Octane0411/open-vibe-island). Both are
> GPL v3; see [NOTICE](NOTICE) for attribution.

## Features

- **Agent monitoring** — see running Claude Code sessions in the notch, approve
  or deny permission prompts inline, and jump back to the originating terminal.
- Media controls and live activities for playback, focus, recording, battery,
  and more.
- System insight: CPU, GPU, memory, network, and disk.
- Productivity tools: timers, clipboard history, color picker, calendar, an
  embedded terminal, and a file shelf.
- Customizable layout, animations, and hover behavior.

## Requirements

- macOS 14+ (Apple Silicon or Intel)
- Full Xcode (the project builds a Metal shader via SwiftTerm)

## Build & run

```bash
# Open in Xcode and run the "DynamicIsland" scheme, or from the CLI:
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Debug -destination 'platform=macOS' build
```

The agent-monitoring engine lives in `Packages/OpenIslandEngine` (a local Swift
package). Its tests run with:

```bash
cd Packages/OpenIslandEngine && swift test
```

## Enabling agent monitoring

1. Open **Settings ▸ Developer ▸ Agents** and toggle **Enable agent monitoring**.
2. Click **Install hooks** to register VibeIsland's Claude Code hooks.
3. Start a new `claude` session in a terminal — it appears in the notch.

## License

GPL v3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
