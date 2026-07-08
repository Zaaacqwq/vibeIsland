# Agent Hook — Fresh-Install Test Plan

Verifies that a user on a **brand-new machine that has never installed
VibeIsland** can install each coding-agent integration and get the three
advertised capabilities working: **Live sessions** (halo + status),
**In-notch actions** (answer / approve / deny), and **Usage data**.

Two layers cover this:

| Layer | Covers | How to run |
| --- | --- | --- |
| **Automated** — `FreshInstallInstallerTests.swift` | Installer/plugin config correctness: fresh install writes the right hook command for every event, re-install is idempotent (no duplicates), legacy entries are scrubbed, uninstall is clean, user config is preserved. | `cd Packages/OpenIslandEngine && swift test --filter FreshInstall` |
| **Manual** — this document | The GUI + runtime parts a unit test can't see: the Settings install click, the notch halo/status, the approve/deny popup, and live usage numbers. | Follow the cases below on a real machine. |

> The automated layer is the regression guard for the two issues found in
> manual testing: a **stale legacy `OpenIslandHooks` hook** and **duplicate
> Codex `PermissionRequest` hooks** (which hang approvals — two blocking hooks,
> one answer). `codexScrubsLegacyDuplicate` and the `*ReinstallIdempotent`
> cases fail if either regresses.

---

## Simulating a fresh machine

A real "never installed" state means no agent-side config yet. To reproduce it
without a second Mac, back up and clear the relevant files, then let VibeIsland
install from scratch:

```bash
ts=$(date +%s)
mkdir -p ~/vibeisland-testbak-$ts
# Claude / Codex / Cursor / Gemini / OpenCode / Antigravity config
mv ~/.claude/settings.json                       ~/vibeisland-testbak-$ts/ 2>/dev/null
mv ~/.codex/hooks.json                            ~/vibeisland-testbak-$ts/ 2>/dev/null
mv ~/.cursor/hooks.json                           ~/vibeisland-testbak-$ts/ 2>/dev/null
mv ~/.gemini/settings.json                        ~/vibeisland-testbak-$ts/ 2>/dev/null
mv ~/.config/opencode/config.json                 ~/vibeisland-testbak-$ts/ 2>/dev/null
rm -rf ~/.gemini/config/plugins/vibeisland ~/.config/opencode/plugins/open-island.js
# Also clear any prior managed binary so install lays down a fresh copy
rm -rf "~/Library/Application Support/OpenIsland"
echo "backed up to ~/vibeisland-testbak-$ts"
```

Restore afterwards by moving the files back.

---

## Preconditions (PRE)

- [ ] **PRE-1** App launches; menu-bar/notch appears. `pgrep -lf VibeIsland` shows the process.
- [ ] **PRE-2** Settings → Developer → Agents → **Enable agent monitoring** is ON.
- [ ] **PRE-3** Bridge socket is live: `lsof -U | grep agent-bridge.sock` shows VibeIsland listening on `~/Library/Application Support/VibeIsland/agent-bridge.sock`.
- [ ] **PRE-4** Each agent CLI is installed and authenticated: `claude`, `codex`, `cursor-agent`, `gemini`, `agy`, `opencode`.

## Install (INS) — do this per agent in Settings → Developer → Agents

For every agent (Claude, Codex, Cursor, Gemini, Antigravity, OpenCode):

- [ ] **INS-1** Click **Install** for the agent; the row shows an installed/managed state.
- [ ] **INS-2** The written config points at the **current** managed binary and **no** legacy `OpenIsland/bin/OpenIslandHooks` path, with **exactly one** managed entry per event. Quick check:
  ```bash
  # nested-schema agents (claude/codex/cursor/gemini) — expect 1 per event, no legacy path
  python3 - <<'PY'
  import json
  for name,p in {"claude":"~/.claude/settings.json","codex":"~/.codex/hooks.json",
                 "cursor":"~/.cursor/hooks.json","gemini":"~/.gemini/settings.json"}.items():
      import os; p=os.path.expanduser(p)
      try: h=json.load(open(p)).get("hooks",{})
      except Exception as e: print(name,"MISSING",e); continue
      for ev,blocks in h.items():
          n=sum(len(b.get("hooks",[])) for b in (blocks if isinstance(blocks,list) else []))
          bad=json.dumps(blocks).lower().count("openisland/bin")
          print(name,ev,"count=",n,"LEGACY!" if bad else "")
  PY
  ```
  - Antigravity: `~/.gemini/config/plugins/vibeisland/hooks.json` exists **and** the plugin is registered in `~/.gemini/config/import_manifest.json`.
  - OpenCode: `~/.config/opencode/plugins/open-island.js` exists and is listed in `~/.config/opencode/config.json` `"plugin"`.
- [ ] **INS-3** Re-click **Install**; config is unchanged (no duplicate entries appear). *(This is what the automated `*ReinstallIdempotent` tests assert.)*

---

## Runtime cases

Start each agent in its own terminal, in a throwaway working directory. Watch
the notch (top-center). To read the per-agent status label, hover the notch to
open it and look at the **Agents** panel.

### TC-LIVE — Live sessions (halo + status)

| # | Agent | Steps | Expected |
| --- | --- | --- | --- |
| LIVE-1 | Claude | `claude`, send any prompt | Notch shows a **halo** while working; Agents panel row `Claude · … — Thinking/Executing`, transitions to complete |
| LIVE-2 | Codex | `codex`, send any prompt | Halo while working; row shows Codex thinking/executing → complete |
| LIVE-3 | Gemini | `gemini`, send a prompt | Row `Gemini CLI · … — Thinking`, then complete |
| LIVE-4 | Cursor | `cursor-agent`, send a prompt | Row `Cursor · … — Thinking`, then complete |
| LIVE-5 | Antigravity | `agy`, ask it to run a shell command | Row `Antigravity · … — Executing`, then completes (auto-completes within a few seconds) |
| LIVE-6 | OpenCode | `opencode`, send a prompt | Row `OpenCode · … — Thinking`, then complete |

Pass = the session appears with the documented status label and a halo when active.

### TC-ACT — In-notch actions

| # | Agent | Steps | Expected (per README) |
| --- | --- | --- | --- |
| ACT-1 | Claude | Ask it to run a command needing approval, e.g. `touch x && curl -s https://example.com -o /dev/null` | Notch auto-expands: **NEEDS PERMISSION**, command shown, **Deny ⌘N / Allow ⌘Y**. Press **⌘Y** → terminal shows `Allowed by PermissionRequest hook` and the agent proceeds |
| ACT-2 | Codex | Ask it to run a **network** command: `curl -s https://example.com -o /dev/null` | Notch shows **Run Bash command … / Deny ⌘N / Allow ⌘Y**; terminal blocks on `Running PermissionRequest hook` (singular — **not** "2"). ⌘Y → `Ran … successfully`. **If it says "Running 2 … hooks" and hangs after ⌘Y, INS config has a duplicate — re-run Install** |
| ACT-3 | OpenCode | With `permission` set to `ask` for `bash`/`edit`, ask it to edit a file | Notch shows an approve/answer card; ⌘Y/⌘N or ⌘1–9 answers it. *If OpenCode never prompts, its own `permission` config isn't gating (schema differs by version) — fix OpenCode config, not VibeIsland* |
| ACT-4 | Cursor | Ask it to run a command not in its allowlist | Notch shows a **red input-needed halo** (+ sound); **no** in-notch buttons — you answer in Cursor's own prompt (jump-back available) |
| ACT-5 | Gemini | Trigger a tool it must confirm | Status/halo only; answered in Gemini's TUI (no in-notch buttons — by design) |
| ACT-6 | Antigravity | `agy` runs a command needing approval | Status/halo only; answered in agy's TUI (no in-notch buttons — by design) |

Notes:
- Approve/deny in the notch is driven by **global ⌘Y / ⌘N** hotkeys (they work regardless of the frontmost app).
- ACT-4/5/6 having **no** in-notch buttons is a **pass**, not a bug — those tools expose no channel to send an answer back.

### TC-USE — Usage data

| # | Steps | Expected |
| --- | --- | --- |
| USE-1 | Open the notch → **Agents** panel | Provider rate windows render (e.g. Claude `5h`/`7d`, Codex `5h`/`7d`) with live percentages |
| USE-2 | Open the usage detail / provider pager | Current **tokens, cost, cache, active time** show and reflect the sessions just run; per-provider cards cycle |
| USE-3 | Run a session, re-open usage | Numbers move (tokens/cost increase) after activity |

---

## Results matrix (fill per run)

| Agent | INS | LIVE | ACT | USE |
| --- | --- | --- | --- | --- |
| Claude | ☐ | ☐ | ☐ answer+approve | ☐ |
| Codex | ☐ | ☐ | ☐ approve (Q read-only) | ☐ |
| Cursor | ☐ | ☐ | ☐ halo only | ☐ |
| Gemini | ☐ | ☐ | ☐ halo only | ☐ |
| Antigravity | ☐ | ☐ | ☐ halo only | ☐ |
| OpenCode | ☐ | ☐ | ☐ answer+approve | ☐ |

Mark **PASS / PARTIAL / FAIL** and note the failing step id (e.g. `ACT-2 hang`).
