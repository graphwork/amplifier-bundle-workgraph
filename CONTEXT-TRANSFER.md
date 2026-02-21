# Context Transfer: amplifier-bundle-workgraph

## Current State (as of 2026-02-21)

- **Git**: `main` — 3 commits, remote at `https://github.com/ramparte/amplifier-bundle-workgraph`
- **Version**: 0.2.0
- **Tests**: 21/21 quick (all passing); full e2e adds ~5 more assertions

## Setup Improvements (2026-02-21)

This section documents the improvements made in version 0.2.0 to address setup friction.

### Problem Areas Identified

1. **Two-sided install** — Users had to run bundle add + executor install + config separately
2. **Per-project executor copies** — No version tracking, users couldn't detect staleness
3. **Wrapper script interface mismatch** — Large prompts could exceed ARG_MAX
4. **Provider patching friction** — Cache gets overwritten on `amplifier update`

### Changes Implemented

#### 1. Version-Stamped Executor Files

Added version comments to executor files for staleness detection:

- `executor/amplifier.toml` — Line 1: `# amplifier-bundle-workgraph v0.2.0`
- `executor/amplifier-run.sh` — Line 2: `# amplifier-bundle-workgraph v0.2.0`

The SessionStart hook and `setup.sh --check` read this version to detect mismatches.

#### 2. SessionStart Hook for Environment Validation

Created `hooks/workgraph-setup/` with:
- `hooks.json` — Hook configuration for SessionStart event
- `check-setup.sh` — Validation script that checks:
  - wg is on PATH
  - Executor TOML exists and version matches
  - Wrapper script exists and is executable
  - Coordinator executor is set to amplifier
  - Provider patch staleness (if source override exists)

The hook injects warnings into agent context when problems are found.

#### 3. Smarter setup.sh

Rewrote `setup.sh` with:
- `--check` mode — Validate without modifying, exit 0 if healthy
- `--force` mode — Overwrite existing executor files
- Version detection — Compares installed executor version to bundle version
- Hook installation — Installs the SessionStart validation hook
- Provider patch check — Informs user if cache sync may be needed
- Clear exit codes: 0=success, 1=validation failure, 2=missing prerequisites

#### 4. Provider Patch Sync Helper

Created `scripts/sync-provider-cache.sh` that:
- Reads source override path from `~/.amplifier/settings.yaml`
- Finds cached provider-openai module
- Syncs `__init__.py` from source to cache
- Reports status (already in sync / synced / error)

#### 5. ARG_MAX Guard

Added size check in `executor/amplifier-run.sh`:
```bash
PROMPT_SIZE=${#PROMPT}
if [ "$PROMPT_SIZE" -gt 131072 ]; then
    echo "Warning: Prompt is ${PROMPT_SIZE} bytes (>128KB). May hit ARG_MAX limits." >&2
fi
```

#### 6. Executor Protocol in Behavior Context

Updated `behaviors/workgraph.yaml` to include both context files:
```yaml
context:
  include:
    - workgraph:context/workgraph-guide.md
    - workgraph:context/wg-executor-protocol.md
```

#### 7. README Restructure

Restructured README.md:
- Quick Start section leads with `setup.sh`
- Troubleshooting section covering all known failure modes
- Manual Installation moved to appendix (Advanced section)
- Validating Your Setup section with `--check` and tests

#### 8. Hook-Shell Module Added

Updated `bundle.md` to include hook-shell module:
```yaml
hooks:
  - module: hook-shell
    config:
      enabled: true
```

This enables the SessionStart hook to fire on every Amplifier session.

## File Layout

```
amplifier-bundle-workgraph/
  bundle.md                        # Root bundle (includes hook-shell)
  setup.sh                        # One-command setup (NEW: --check, --force)
  behaviors/workgraph.yaml        # Behavior (includes executor protocol context)
  context/
    workgraph-guide.md             # Full wg CLI guide for agents
    wg-executor-protocol.md       # Protocol for executor-spawned agents
  agents/
    workgraph-planner.md          # Task decomposition specialist
  executor/
    amplifier.toml                # Workgraph executor config (type=claude, version stamp)
    amplifier-run.sh              # Wrapper script (version stamp, ARG_MAX guard)
    install.sh                    # Legacy install script
  hooks/
    workgraph-setup/              # NEW: SessionStart validation hook
      hooks.json
      check-setup.sh
  scripts/
    sync-provider-cache.sh        # NEW: Provider cache sync helper
  tests/
    test_integration.sh          # 21 quick + e2e lifecycle tests
  README.md                      # Restructured with troubleshooting
  CONTEXT-TRANSFER.md            # This file
```

## Remaining / Future Work

- [ ] Coordinate with graphwork on the executor interface (they may want to standardize a non-claude mechanism for prompt passing)
- [ ] Consider publishing under `graphwork/` namespace vs `ramparte/`
- [ ] Consider a recipe for "decompose and execute" workflow (multi-step: planner → wg init → add tasks → wg service start)
- [ ] File feature request against amplifier for `amplifier run --stdin` or `--prompt-file` to avoid ARG_MAX issues

## How to Use

```bash
# RECOMMENDED: One-command setup
./setup.sh

# Check setup health without modifying
./setup.sh --check

# After amplifier update, sync provider patches
./scripts/sync-provider-cache.sh

# Add bundle to amplifier manually (if not using setup.sh)
amplifier bundle add git+https://github.com/graphwork/amplifier-bundle-workgraph

# Use in a session
amplifier run -B workgraph

# Full e2e test (needs wg on PATH)
export PATH="$HOME/dev/ANext/workgraph/target/release:$PATH"
cd ~/dev/ANext/amplifier-bundle-workgraph
bash tests/test_integration.sh
```
