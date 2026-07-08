# CLAUDE.md

See [AGENTS.md](./AGENTS.md) for build/run instructions and project notes.

**Build & restart the app (do NOT use `CODE_SIGNING_ALLOWED=NO` — it causes
Keychain re-prompts):**

```bash
killall VibeIsland 2>/dev/null
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/DynamicIsland-fzjfxneazwzuqfezeiyhaagwpagh/Build/Products/Debug/VibeIsland.app
```
