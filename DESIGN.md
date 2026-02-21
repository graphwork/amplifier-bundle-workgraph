# Design: Setup Improvements for amplifier-bundle-workgraph

**Date**: 2026-02-21
**Status**: Proposal (iteration 0)
**Scope**: What we control now — no upstream changes to workgraph or amplifier-core

---

## Problem Analysis

The current setup experience has four friction areas. This section catalogs each one, explains why it hurts, and identifies what we can change.

### 1. Two-Sided Install (Bundle + Executor)

**What happens today**: Users must run two independent install flows:
1. `amplifier bundle add git+https://...` — installs the bundle (context, behavior, planner agent)
2. `./executor/install.sh /path/to/project` — copies `amplifier.toml` + `amplifier-run.sh` into `.workgraph/executors/`
3. `wg config --coordinator-executor amplifier` — sets executor as default

**Why it hurts**: Users forget one side. The bundle and executor feel like separate products, but they're one integration. `setup.sh` unifies them, but the README leads with manual steps. If the executor isn't installed, `wg service start` will silently fail to invoke amplifier, and the error message gives no hint about the missing executor.

**What we control**: `setup.sh`, README ordering, SessionStart hooks via hook-shell module.

### 2. Per-Project Executor Copy

**What happens today**: `install.sh` copies `amplifier.toml` and `amplifier-run.sh` into every project's `.workgraph/executors/`. When the bundle updates, those copies go stale. There's no version marker, so users can't detect drift.

**Why it hurts**: Users end up with different executor versions across projects. The wrapper script and prompt template in the TOML are tightly coupled to the bundle version but aren't tracked together. After a bundle update, old executor copies still reference the old prompt template, potentially missing new workgraph protocol fields.

**What we control**: `install.sh`, `setup.sh`, and we can add version stamping to executor files.

### 3. Wrapper Script Interface Mismatch

**What happens today**: `amplifier-run.sh` exists solely to bridge two interface mismatches:
- Workgraph pipes the prompt via stdin (but only for `type = "claude"` — see `spawn.rs:336`)
- `amplifier run --mode single` takes the prompt as a positional argument

So we use `type = "claude"` (misleading — we're not using Claude) and a wrapper that does `PROMPT=$(cat); exec amplifier run ... "$PROMPT"`.

**Why it hurts**: The `type = "claude"` is confusing. The wrapper adds a moving part. Large prompts could exceed shell argument limits (`ARG_MAX`, typically 2MB on Linux). The indirection makes debugging executor failures harder — users see "amplifier-run.sh" in error traces, not "amplifier run".

**What we control**: The wrapper script, the TOML config. We **cannot** change workgraph's stdin behavior (would need `spawn.rs` change) or amplifier's CLI interface (would need `--stdin` or `--prompt-file` flag upstream).

### 4. Provider Patching Friction

**What happens today**: OpenRouter users with patched `provider-openai` must:
1. Keep a patched copy in a development directory
2. Register it: `amplifier source add provider-openai /path/to/patch`
3. After every `amplifier update`, manually copy the patched `__init__.py` to `~/.amplifier/cache/amplifier-module-provider-openai-*/`

The source override in `settings.yaml` survives `amplifier update`, but it's the cached pip package that Python actually imports at runtime.

**Why it hurts**: `amplifier update` silently overwrites the cache. The next session uses the unpatched module. There's no warning or detection.

**What we control**: Documentation, a SessionStart hook that detects staleness, and a helper script. We cannot change amplifier's module loading to prefer source overrides over cache (that's an amplifier-core architectural issue, and the settings.yaml entry *is* the override — the cache rebuild is the bug).

---

## Design: Concrete Changes

### Change 1: Version-Stamped Executor Files

**Goal**: Enable staleness detection for per-project executor copies.

**Mechanism**: Add a version header comment to `amplifier.toml` and `amplifier-run.sh`. The version matches `bundle.md`'s `version` field (currently `0.2.0`).

**Files to modify**:

| File | Change |
|------|--------|
| `executor/amplifier.toml` | Add `# amplifier-bundle-workgraph v0.2.0` as first line |
| `executor/amplifier-run.sh` | Add `# amplifier-bundle-workgraph v0.2.0` after shebang |

**Version format** (in `amplifier.toml`, line 1):
```toml
# amplifier-bundle-workgraph v0.2.0
```

**Version format** (in `amplifier-run.sh`, line 2):
```bash
#!/usr/bin/env bash
# amplifier-bundle-workgraph v0.2.0
```

The SessionStart hook (Change 2) and `setup.sh --check` (Change 3) read this line and compare it to the installed bundle's version. No functional changes — this is metadata only.

---

### Change 2: SessionStart Hook for Environment Validation

**Goal**: Automatically verify the setup is healthy when an Amplifier session starts in a workgraph-related context.

**Mechanism**: Use the `hook-shell` module's `SessionStart` event. Install a shell hook at `.amplifier/hooks/workgraph-setup/` that runs on every session start (with `matcher: "startup"`).

**What the hook checks**:
1. `wg` is on `PATH`
2. If `.workgraph/` exists in the project directory:
   - `.workgraph/executors/amplifier.toml` exists
   - `amplifier-run.sh` exists and is executable
   - Executor version matches bundle version (reads version header from Change 1)
   - Coordinator executor is set to `amplifier` (checks `config.toml`)
3. Provider patch staleness: if `~/.amplifier/settings.yaml` has a source override for `provider-openai`, diff the override's `__init__.py` against the cached copy

**Output**: Uses `contextInjection` JSON response to inject a warning into the agent's context when problems are found. Does NOT block the session (exit 0 always) — just warns.

**Files to create**:

| File | Purpose |
|------|---------|
| `hooks/workgraph-setup/hooks.json` | Hook configuration |
| `hooks/workgraph-setup/check-setup.sh` | Validation script |

**Hook config** (`hooks/workgraph-setup/hooks.json`):
```json
{
  "description": "Verify workgraph+amplifier setup health on session start",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "${AMPLIFIER_HOOKS_DIR}/workgraph-setup/check-setup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Validation script** (`hooks/workgraph-setup/check-setup.sh`) pseudocode:
```bash
#!/usr/bin/env bash
set -euo pipefail

ISSUES=()
BUNDLE_VERSION="0.2.0"  # Keep in sync with bundle.md

# 1. Check wg on PATH
command -v wg &>/dev/null || ISSUES+=("wg CLI not found on PATH")

# 2. Check .workgraph/ — only run executor checks if it's a wg project
if [ -d ".workgraph" ]; then
    # 3. Executor TOML
    if [ ! -f ".workgraph/executors/amplifier.toml" ]; then
        ISSUES+=("Executor not installed (.workgraph/executors/amplifier.toml missing). Run setup.sh.")
    else
        # 4. Version check
        INSTALLED_VER=$(head -1 .workgraph/executors/amplifier.toml | grep -oP 'v\K[0-9.]+' || echo "unknown")
        if [ "$INSTALLED_VER" != "$BUNDLE_VERSION" ]; then
            ISSUES+=("Executor version mismatch: installed v${INSTALLED_VER}, bundle v${BUNDLE_VERSION}. Run setup.sh to upgrade.")
        fi
    fi

    # 5. Wrapper script
    if [ ! -x ".workgraph/executors/amplifier-run.sh" ]; then
        ISSUES+=("amplifier-run.sh missing or not executable")
    fi

    # 6. Coordinator config
    if [ -f ".workgraph/config.toml" ]; then
        grep -q 'executor.*=.*"amplifier"' .workgraph/config.toml 2>/dev/null \
            || ISSUES+=("Amplifier not set as default executor (run: wg config --coordinator-executor amplifier)")
    fi
fi

# 7. Provider patch check (only if source override exists)
SETTINGS="$HOME/.amplifier/settings.yaml"
if [ -f "$SETTINGS" ]; then
    OVERRIDE=$(python3 -c "
import yaml
with open('$SETTINGS') as f:
    cfg = yaml.safe_load(f)
p = cfg.get('sources',{}).get('modules',{}).get('provider-openai','')
if p: print(p)
" 2>/dev/null || true)

    if [ -n "$OVERRIDE" ] && [ -d "$OVERRIDE" ]; then
        CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
        if [ -n "$CACHE_DIR" ]; then
            SRC="$OVERRIDE/amplifier_module_provider_openai/__init__.py"
            DST="$CACHE_DIR/amplifier_module_provider_openai/__init__.py"
            if [ -f "$SRC" ] && [ -f "$DST" ]; then
                diff -q "$SRC" "$DST" &>/dev/null \
                    || ISSUES+=("Provider-openai cache out of sync with source override. Run: scripts/sync-provider-cache.sh")
            fi
        fi
    fi
fi

# Output
if [ ${#ISSUES[@]} -eq 0 ]; then
    exit 0  # All good, no context injection
fi

# Build warning message
MSG="WORKGRAPH SETUP ISSUES:\\n"
for issue in "${ISSUES[@]}"; do
    MSG+="  - $issue\\n"
done

printf '{"contextInjection": "%s"}' "$MSG"
exit 0
```

**How the hook gets installed**: `setup.sh` (Change 3) copies the `hooks/workgraph-setup/` directory to `.amplifier/hooks/workgraph-setup/`. The hook-shell module auto-discovers hooks in `.amplifier/hooks/*/hooks.json`.

**Bundle dependency**: `bundle.md` must include `hook-shell` as a module so the hooks actually fire. Add to `bundle.md` frontmatter:
```yaml
hooks:
  - module: hook-shell
    config:
      enabled: true
```

---

### Change 3: Smarter setup.sh

**Goal**: Make `setup.sh` the single recommended entry point. Make it idempotent, informative, and diagnostic.

**Files to modify**: `setup.sh`

**New interface**:
```
setup.sh [--check] [--force] [PROJECT_DIR]

  --check       Report status without modifying anything. Exit 0 if healthy, 1 if not.
  --force       Overwrite existing executor files even if version matches.
  PROJECT_DIR   Target project directory (default: current directory).
```

**New flow**:
```
=== Amplifier + Workgraph Setup (v0.2.0) ===

[1/5] Checking prerequisites...
      wg:        /usr/local/bin/wg ✓
      amplifier: /usr/local/bin/amplifier ✓

[2/5] Adding workgraph bundle to Amplifier...
      Bundle 'workgraph' v0.2.0 installed ✓

[3/5] Installing Amplifier executor...
      .workgraph/executors/amplifier.toml ✓
      .workgraph/executors/amplifier-run.sh ✓ (executable)

[4/5] Setting default executor...
      wg config --coordinator-executor amplifier ✓

[5/5] Installing setup validation hook...
      .amplifier/hooks/workgraph-setup/ ✓

=== Setup Complete ===

Usage:
  amplifier run -B workgraph    # Interactive session with wg awareness
  wg service start              # Auto-spawn Amplifier for each task
  ./setup.sh --check            # Verify setup health
```

**Key improvements over current setup.sh**:
1. Version display in header
2. `--check` mode runs the same validation as the SessionStart hook
3. Validates bundle actually loaded after `amplifier bundle add` (checks `amplifier bundle list`)
4. Detects existing executor, compares versions, warns before overwriting (unless `--force`)
5. Installs the SessionStart hook to `.amplifier/hooks/`
6. Provider patch check at end
7. Clear exit codes: 0 = success, 1 = validation failure, 2 = missing prerequisites

---

### Change 4: Provider Patch Sync Helper

**Goal**: One-command fix for the "cache out of sync after `amplifier update`" problem.

**Files to create**: `scripts/sync-provider-cache.sh`

**Script logic**:
```bash
#!/usr/bin/env bash
# Sync provider-openai source override to Amplifier cache.
# Run this after `amplifier update` if you use a patched provider.
set -euo pipefail

SETTINGS="$HOME/.amplifier/settings.yaml"

# Read source override path from settings
SOURCE_PATH=$(python3 -c "
import yaml
with open('$SETTINGS') as f:
    cfg = yaml.safe_load(f)
p = cfg.get('sources',{}).get('modules',{}).get('provider-openai','')
if p: print(p)
" 2>/dev/null)

if [ -z "$SOURCE_PATH" ]; then
    echo "No source override for provider-openai in ~/.amplifier/settings.yaml"
    exit 0
fi

CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
if [ -z "$CACHE_DIR" ]; then
    echo "No cached provider-openai module found in ~/.amplifier/cache/"
    exit 1
fi

SRC="$SOURCE_PATH/amplifier_module_provider_openai/__init__.py"
DST="$CACHE_DIR/amplifier_module_provider_openai/__init__.py"

if diff -q "$SRC" "$DST" &>/dev/null; then
    echo "Cache already matches source override. No sync needed."
    exit 0
fi

echo "Syncing provider-openai:"
echo "  Source: $SRC"
echo "  Cache:  $DST"
cp "$SRC" "$DST"
echo "Done ✓"
```

---

### Change 5: ARG_MAX Guard in Wrapper Script

**Goal**: Prevent silent failures when prompts exceed shell argument limits.

**Files to modify**: `executor/amplifier-run.sh`

**Change**: Add a size check before passing the prompt as a positional arg. If the prompt exceeds 128KB, warn and proceed (it may still work on Linux where `ARG_MAX` is typically 2MB, but it's a canary).

```bash
# After reading prompt from stdin
PROMPT_SIZE=${#PROMPT}
if [ "$PROMPT_SIZE" -gt 131072 ]; then
    echo "Warning: Prompt is ${PROMPT_SIZE} bytes (>128KB). May hit ARG_MAX limits." >&2
fi
```

**Long-term fix**: File a feature request against amplifier for `amplifier run --stdin` or `amplifier run --prompt-file PATH`. Document the limitation in the README.

---

### Change 6: Include `wg-executor-protocol.md` in Behavior Context

**Goal**: The file `context/wg-executor-protocol.md` exists but is never loaded into agent context. Agents spawned by the executor get partial protocol guidance from the prompt template, but interactive sessions that start `wg service start` don't understand the executor protocol at all.

**Files to modify**: `behaviors/workgraph.yaml`

**Change**:
```yaml
context:
  include:
    - workgraph:context/workgraph-guide.md
    - workgraph:context/wg-executor-protocol.md
```

---

### Change 7: README Restructure

**Goal**: Lead with `setup.sh`, push manual steps to an appendix, add troubleshooting.

**Files to modify**: `README.md`

**New structure**:
```
# amplifier-bundle-workgraph

## Quick Start
  ./setup.sh                        ← THE path for new users

## What This Does
  Two integration directions (keep existing content)

## How It Works
  Architecture diagram (keep existing)

## Troubleshooting
  NEW section covering:
  - "wg: command not found"
  - "Executor not installed / version mismatch"
  - "Empty prompt error from amplifier-run.sh"
  - "Agent doesn't know wg commands" (missing -B workgraph)
  - "Provider patches lost after amplifier update"
  - "Why does the TOML say type = 'claude'?"

## Configuration
  Timeouts, max agents, custom bundles (keep existing)

## Validating Your Setup
  ./setup.sh --check
  ./tests/test_integration.sh --quick

## Manual Installation (Advanced)
  Moved from current Quick Start — for users who want piece-by-piece control

## File Layout
## Testing
```

---

## Implementation Order

| Phase | Step | Files | Risk | Dependencies |
|-------|------|-------|------|-------------|
| **1. Foundation** | 1a. Version-stamp executor files | `executor/amplifier.toml`, `executor/amplifier-run.sh` | Low | None |
| | 1b. Include executor protocol in behavior | `behaviors/workgraph.yaml` | Low | None |
| | 1c. Create provider sync script | `scripts/sync-provider-cache.sh` | Low | None |
| **2. Hooks** | 2a. Create SessionStart hook | `hooks/workgraph-setup/hooks.json`, `hooks/workgraph-setup/check-setup.sh` | Medium | 1a (reads version) |
| | 2b. Add hook-shell to bundle | `bundle.md` | Low | 2a |
| **3. Setup** | 3a. Rewrite setup.sh | `setup.sh` | Medium | 1a, 2a (installs hooks) |
| | 3b. Add ARG_MAX guard | `executor/amplifier-run.sh` | Low | None |
| **4. Docs** | 4a. Restructure README | `README.md` | Low | All above (describes them) |
| | 4b. Update CONTEXT-TRANSFER.md | `CONTEXT-TRANSFER.md` | Low | All above |
| **5. Test** | 5a. Add tests for new components | `tests/test_integration.sh` | Low | All above |

**Testing at each phase**:
- Phase 1: `./tests/test_integration.sh --quick` (existing tests still pass)
- Phase 2: Manual: `amplifier run -B workgraph` in a project with/without executor → hook fires
- Phase 3: `./setup.sh --check` in clean dir, set-up dir, half-set-up dir
- Phase 4: Read-through, verify all links and troubleshooting steps
- Phase 5: `./tests/test_integration.sh --quick` (all new + existing tests pass)

---

## Files Summary

### New files
| File | Purpose |
|------|---------|
| `hooks/workgraph-setup/hooks.json` | SessionStart hook config for setup validation |
| `hooks/workgraph-setup/check-setup.sh` | Shell script that checks setup health |
| `scripts/sync-provider-cache.sh` | One-command provider cache sync helper |

### Modified files
| File | Changes |
|------|---------|
| `executor/amplifier.toml` | Add version comment (line 1) |
| `executor/amplifier-run.sh` | Add version comment (line 2), ARG_MAX guard |
| `behaviors/workgraph.yaml` | Add `wg-executor-protocol.md` to context includes |
| `bundle.md` | Add `hook-shell` module dependency |
| `setup.sh` | Full rewrite: --check mode, version detection, hook install, provider check |
| `README.md` | Restructure: setup.sh-first, troubleshooting section, manual install moved to appendix |
| `CONTEXT-TRANSFER.md` | Update remaining work, record new features |
| `tests/test_integration.sh` | Add tests for hook, setup --check, provider sync, version stamps |

### Unchanged files (and why)
| File | Reason |
|------|--------|
| `context/workgraph-guide.md` | Content is stable |
| `context/wg-executor-protocol.md` | Content is stable (now included via behavior) |
| `agents/workgraph-planner.md` | Agent definition is stable |
| `executor/install.sh` | Copies files verbatim — works with version-stamped files automatically |

---

## What We're NOT Doing (and Why)

1. **Not changing workgraph's stdin behavior** — Would require upstream change to `spawn.rs:336`. The `type = "claude"` hack works. Document it clearly instead.

2. **Not adding `--prompt-file` or `--stdin` to amplifier CLI** — Requires upstream change. File as feature request. The current approach works for typical prompt sizes (<128KB).

3. **Not auto-fixing provider cache on session start** — Too dangerous to silently overwrite cached files. The hook warns, the user runs the sync script explicitly.

4. **Not removing per-project executor copies** — Workgraph requires executors in `.workgraph/executors/`. What we can do is detect staleness via version stamps.

5. **Not inlining the wrapper into the TOML** — Tempting (`command = "bash"`, `args = ["-c", "..."]`), but shell quoting inside TOML strings is fragile and harder to debug than a separate script. Keep `amplifier-run.sh`.

6. **Not adding a `--bundle` flag to the executor install** — The TOML already has `args = ["--bundle", "workgraph"]`. Making this configurable adds complexity for a rare use case.

---

## Success Criteria

After implementing this design:

| Scenario | Expected Experience |
|----------|-------------------|
| **New user** | Runs `./setup.sh`. Gets working setup with validation hook. Starts session, sees no warnings. `wg service start` works. |
| **Existing user after bundle update** | Starts a session. SessionStart hook detects stale executor. Warning tells them to run `./setup.sh`. |
| **User after `amplifier update`** | SessionStart hook detects provider cache mismatch. Warning tells them to run `scripts/sync-provider-cache.sh`. |
| **User debugging a failure** | Runs `./setup.sh --check` for full diagnostic. README troubleshooting covers every known failure mode. |
| **Developer updating the bundle** | Bumps version in `bundle.md`, `amplifier.toml`, `amplifier-run.sh`, `check-setup.sh`. Tests catch version mismatches. |
