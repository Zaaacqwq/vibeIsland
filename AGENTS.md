# AGENTS.md — VibeIsland

Instructions for any coding agent (Claude Code, Codex, OpenCode, Cursor, …)
working on this repo.

## Build, run, and restart the app

Always use this exact sequence to build and (re)launch the macOS app. Run it
from the repo root (`/Users/zaaac/Documents/Code/vibeIsland`):

```bash
killall VibeIsland 2>/dev/null
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/DynamicIsland-fzjfxneazwzuqfezeiyhaagwpagh/Build/Products/Debug/VibeIsland.app
```

- `killall VibeIsland` quits the currently-running instance so `open` launches
  the freshly built one (otherwise the old copy keeps running).
- The scheme/target is `DynamicIsland`; the built app bundle is named
  **`VibeIsland.app`**.
- The launch path is the Xcode DerivedData Debug product. If that path no longer
  exists, find it with:
  `xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2"/VibeIsland.app"}'`

### Do NOT pass `CODE_SIGNING_ALLOWED=NO`

Building with `CODE_SIGNING_ALLOWED=NO` produces an **ad-hoc / unsigned** binary
whose code signature changes on every rebuild. macOS gates Keychain access by
code signature, so an ad-hoc build makes the app **re-prompt for Keychain
access** (e.g. `com.zaaacqwq.VibeIsland.antigravity-oauth`, the Cursor session
token) on every relaunch — the "Always Allow" you grant is tied to that one
build and is lost on the next rebuild. The plain `build` above keeps the
project's normal signing so Keychain/TCC authorizations persist.

## Notes

- Swift package engine lives in `Packages/OpenIslandEngine` (targets:
  `OpenIslandCore`, `VibeIslandAgentKit`, `OpenIslandHooks`). For fast
  compile-only checks of engine changes: `cd Packages/OpenIslandEngine && swift build`
  and `swift test` (test target: `VibeIslandAgentKitTests`).
- `Contents/Helpers/OpenIslandHooks` is a **checked-in prebuilt universal
  binary** (the hooks CLI), NOT compiled by the app build. If you change engine
  sources that the hooks CLI uses (e.g. `CursorHooks`, `OpenIslandHooksCLI`),
  rebuild it and replace the artifact:
  `swift build -c release --arch arm64 --arch x86_64 --product OpenIslandHooks`
  then copy `.build/apple/Products/Release/OpenIslandHooks` over
  `Contents/Helpers/OpenIslandHooks` (`codesign --force --sign - <dst>`), then
  rebuild the app so it re-embeds it. The managed copy the CLIs actually invoke
  lives at `~/Library/Application Support/OpenIsland/bin/OpenIslandHooks` and is
  refreshed when the user reinstalls hooks from Settings → Agents.
