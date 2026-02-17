# Context Transfer: amplifier-bundle-workgraph

## Current State (as of 2026-02-17)

- **Git**: `main` — 3 commits, remote at `https://github.com/ramparte/amplifier-bundle-workgraph`
- **Tests**: 21/21 quick (all passing); full e2e adds ~5 more assertions
- **Bundle loading**: Confirmed working — `workgraph-planner` agent and `workgraph-guide.md` context load correctly
- **Executor**: End-to-end verified — workgraph spawns Amplifier, agent creates artifacts, task marked done

## Bugs Fixed (commit fbd612a)

### 1. Executor: No prompt was being passed to amplifier

**Root cause**: Workgraph only pipes prompt to stdin for `type = "claude"` executors. Custom types get `stdin = null`. The original TOML used `type = "amplifier"` which silently dropped the prompt.

**Additionally**: `amplifier run --mode single` requires the prompt as a positional argument, not stdin.

**Fix**: 
- Changed `type = "amplifier"` → `type = "claude"` in `executor/amplifier.toml` (makes workgraph generate `cat prompt.txt | command`)
- Added `executor/amplifier-run.sh` wrapper that reads piped stdin and passes as `"$PROMPT"` arg to amplifier

### 2. Bundle behavior YAML had wrong include format

**Root cause**: 
- `context:` was a bare list (should be `context.include:` dict)
- `agents:` used `source:` key (doesn't exist; should use `agents.include:` list)  
- Agent path had `agents/` prefix (system appends it automatically, causing double-path)

**Fix**: Rewrote `behaviors/workgraph.yaml` with correct format:
```yaml
agents:
  include:
    - workgraph:workgraph-planner
context:
  include:
    - workgraph:context/workgraph-guide.md
```

### 3. bundle.md had wrong include URI format

**Root cause**: Bare relative path `behaviors/workgraph.yaml` — no handler exists for this URI scheme.

**Fix**: `bundle: workgraph:behaviors/workgraph` (namespace path, no extension, bundle: key)

### 4. Test was checking status immediately after non-blocking spawn

**Root cause**: `wg spawn` is non-blocking — it returns after starting the agent process. The test checked status immediately, got "in-progress".

**Fix**: Test now polls with a 120s timeout until status reaches terminal state (done/failed).

## File Layout

```
amplifier-bundle-workgraph/
  bundle.md                        # Root bundle (fixed include URI)
  behaviors/workgraph.yaml         # Behavior (fixed context/agents format)
  context/workgraph-guide.md       # Full wg CLI guide for agents
  context/wg-executor-protocol.md  # Protocol for executor-spawned agents
  agents/workgraph-planner.md      # Task decomposition specialist
  executor/amplifier.toml          # Workgraph executor config (type=claude, wrapper command)
  executor/amplifier-run.sh        # NEW: stdin→arg bridge for amplifier
  executor/install.sh              # Installs both TOML + run.sh
  tests/test_integration.sh        # 21 quick + e2e lifecycle tests
  README.md
```

## Key Design Decisions

- **type = "claude" in executor TOML** — Not because we're using Claude, but because this is the only type workgraph uses to generate `cat prompt.txt | command`. Custom types get null stdin.
- **No custom tool module** — Agents use bash to call `wg` CLI directly (ruthless simplicity)
- **Context-driven** — Bundle value is teaching agents the workgraph mental model via context files
- **Wrapper script approach** — `amplifier-run.sh` bridges the gap between workgraph's stdin-pipe and amplifier's positional-arg requirement

## Workgraph Repo Details

- Located at `~/dev/ANext/workgraph` (cloned, not modified)
- Rust binary at `target/release/wg`
- Key finding from source: `spawn.rs:336` sets `cmd.stdin(Stdio::null())` for all executor types except "claude"

## Remaining / Future Work

- [ ] Coordinate with graphwork on the executor interface (they may want to standardize a non-claude mechanism for prompt passing)
- [ ] Consider publishing under `graphwork/` namespace vs `ramparte/`
- [ ] Consider a recipe for "decompose and execute" workflow (multi-step: planner → wg init → add tasks → wg service start)
- [ ] The `wg` binary must be on PATH when tasks run — document this prerequisite more prominently
- [ ] Consider `context/wg-executor-protocol.md` inclusion in the behavior (currently not included in context.include — agents only get workgraph-guide.md)

## How to Use

```bash
# Install executor in a wg project
~/dev/ANext/amplifier-bundle-workgraph/executor/install.sh /path/to/wg/project

# Add bundle to amplifier
amplifier bundle add ~/dev/ANext/amplifier-bundle-workgraph/bundle.md

# Use in a session
amplifier run --bundle workgraph

# Full e2e test (needs wg on PATH)
export PATH="$HOME/dev/ANext/workgraph/target/release:$PATH"
cd ~/dev/ANext/amplifier-bundle-workgraph
bash tests/test_integration.sh
```
