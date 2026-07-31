# Changelog

All notable changes to VibeIsland, newest first. Versions follow
[semantic versioning](https://semver.org): a minor bump adds features, a patch
bump fixes them.

## 1.4.0

VibeIsland speaks Simplified Chinese, and the music waveform finally reads the
same whatever you play it through.

### Added

- A language preference under General: Follow System, English, or 简体中文.
  Switching restarts the app. Every string in the interface is translated —
  weekday names, month names and durations inside the notch follow the choice
  too, which the system-level language override alone does not do.

### Changed

- Row subtitles across Settings moved into the info popover next to each row's
  existing help text. Notes that describe an operation, prerequisite, privacy
  implication or destructive effect stay visible instead.
- The closed-notch priority list calls the agent activity "Agent" rather than
  "Claude". It has always driven Codex, OpenCode, Gemini, Antigravity, Copilot
  and Cursor sessions as well.

### Fixed

- The real-time waveform no longer looks completely different from one music app
  to the next. It was driven by linear amplitude, which spent half the bar's
  travel inside 6 dB and saturated at a level a loud master clears constantly —
  so a loudness-normalising app and one that ships the raw master, a routine
  8 dB apart, gave you one bar pinned at full height and one that barely moved.
  Band energy is now normalised across a 39 dB window, which costs that same
  8 dB about a fifth of the bar and leaves loud sources room before they pin.
- Headphones and speakers no longer produce an identical waveform at obviously
  different loudness. macOS keeps a separate volume per device and exposes no
  reading of actual output level, so VibeIsland learns where you habitually
  leave the slider on each device and corrects for it: at your usual level every
  route animates alike, while turning it up or down from there still changes the
  bars. A device you have not used before calibrates on first play.
- The waveform amplitude slider shifts quiet and loud passages together instead
  of only stretching the loud ones.
- Lyrics search continues to NetEase and QQ Music when LRCLIB has no entry for a
  track, rather than giving up. Previously it only fell through when LRCLIB
  returned lyrics without a timeline.

## 1.3.1

### Fixed

- The real-time waveform no longer sits still while music plays. 1.3.0 scaled it
  by the output device's decibel amplitude, which is electrically correct and
  visually useless — macOS maps its volume slider logarithmically, so 18% on the
  slider is 1.5% amplitude, and every bar was pinned to the idle floor. It now
  scales by the slider's own value, so quiet playback reads as quieter without
  collapsing.

## 1.3.0

Two new utility tools in the notch, a tab row you can arrange yourself, and a
notch that finally sizes itself correctly.

### Added

- **Color picker.** An eyedropper that samples any pixel on screen, keeps a
  history, and copies in eight formats (HEX, HEX+A, RGB, RGBA, HSL, HSB, SwiftUI,
  `NSColor`). Available as a notch tab or as a header popover, with an optional
  global shortcut that opens the loupe without opening the notch. Colors are
  stored in sRGB so a swatch reads the same hex on any display.
- **Clipboard manager.** Searchable history of text, images and files with
  pinning, source-app attribution and sort modes. Copies that apps mark
  confidential are never recorded — that covers password managers using the
  `org.nspasteboard.ConcealedType` convention plus 1Password's and KeeWeb's own
  markers — and there is a per-app ignore list and an "ignore next copy" escape
  hatch. Selecting an entry copies it; hold ⌥ to paste it, ⌥⇧ to paste it without
  formatting. Optional global shortcut.
- **Rearrangeable tabs.** Hold ⌘ and drag a tab in the open notch to move it.
  The order persists, tabs you switch off keep their place, and Settings ›
  Appearance › Tabs can reset it.
- **Adjustable waveform amplitude.** Settings › Media › Appearance now has a
  25–200% slider for how strongly captured audio drives the real-time waveform.

### Changed

- Tabs show their icon only; the title moved to the hover tooltip. Rendering it
  cost roughly 120pt of notch width, and that width is charged to both sides of
  the header. Settings › Appearance › Tabs can turn titles back on.
- The Home header shows at most three metrics and the Agents header one provider.
  Each extra widget widens the open notch by twice its own width, so the caps keep
  the notch from growing past the point where the tab row swims in dead space.

### Fixed

- **The open notch is sized from both sides of its header.** It used to be sized
  from the tab count alone, so switching tabs off shrank it while the trailing
  side kept its size — the stats widget slid under the physical notch cutout and
  the selected tab's label collapsed. Width now covers whichever side is wider,
  measured per widget.
- Changing AirPods noise cancellation or transparency with the notch open no
  longer replaces the whole header; it appears as a compact header widget, the way
  volume and brightness already did. (macOS draws its own HUD for this from
  Control Center, which cannot be suppressed the way the volume OSD can.)
- Opening Settings › Appearance no longer crashes. The notch-width slider built
  its range from a computed minimum that could exceed its hardcoded ceiling, and
  a range whose lower bound is the larger one traps.
- The real-time waveform now scales with the system output level instead of
  dancing at full height at 5% volume. (The curve this shipped with was far too
  steep and left the bars frozen at normal volumes — fixed in 1.3.1.)
- Seeking inside Spotify's own player is followed again. Spotify does not
  reliably announce scrubs, so the notch kept counting from the old position.

## 1.2.2

### Fixed

- Sparkle appcasts are seeded from `main` rather than from the tag being built,
  so a release no longer drops the entry for the previous one.

### Changed

- The release toolchain is pinned to Xcode 26.5. AppKit and SwiftUI gate
  behaviour on the SDK an app was linked against, and builds linked against the
  26.2 SDK were noticeably less responsive — hover, close and tab switches all
  lagged — on a 26.4 machine.

## 1.2.1

### Fixed

- Caps lock and input source changes show in the open notch's header instead of
  swapping the header for a taller HUD that inflated the whole notch.
- Untimed lyrics are no longer treated as a single synced line.
- The 1.1.5 entry was restored to the update feed.

## 1.2.0

### Added

- **Monitor tab.** CPU, GPU, memory, storage, network, power and displays as an
  overview grid; tap a tile to drill into that category. Off by default; enable it
  in Settings › System Monitor, which also picks which tiles appear.
- Choose which agent providers the notch header shows.

### Changed

- System stats are sampled off the main thread.

### Fixed

- Every notch tab draws at the same height, so switching tabs no longer resizes
  the window.
- The Power tile animates in with the rest of the Monitor grid.

## 1.1.5

### Fixed

- Notch swipes lock to a dominant axis, so a slightly diagonal swipe no longer
  switches tabs and scrolls at the same time.

## 1.1.4

### Fixed

- Weather location resolution no longer falls back to IP geolocation, which could
  place you in the wrong city.

## 1.1.3

### Fixed

- Removed the double blur on the notch expand/collapse transition.
- Eliminated main-thread render stalls that showed up as UI input lag.

## 1.1.2

### Fixed

- The app keeps its v1 identity across updates, so macOS privacy grants and
  Keychain items survive.

## 1.1.1

### Fixed

- Updates preserve settings and app identity.
- The Sparkle appcast is published automatically on release.

## 1.1.0

### Added

- Create calendar events and reminders from the notch.
- Codex hook trust entries are written on install, so agent monitoring works
  without hand-editing Codex's config.

## 1.0.1

### Added

- Zero-setup ad-hoc signing and a DMG release pipeline, so the project builds and
  packages from a fresh clone with no certificate.

### Changed

- Refreshed ReadMe screenshots, added live-activity and HUD galleries, and
  attributed rtaudio, Stats, SkyLightWindow, DynamicNotchKit and Open-Meteo in
  NOTICE.

## 1.0.0

First public release. A Dynamic Island for macOS built on
[boring.notch](https://github.com/TheBoredTeam/boring.notch) and
[Atoll](https://github.com/Ebullioscopic/Atoll): media controls with lyrics and a
visualizer, calendar and reminders, a file shelf, timers, weather, system HUDs
for volume/brightness/backlight, live activities in the closed notch, and
monitoring for coding agents (Claude Code, Codex, and others).
