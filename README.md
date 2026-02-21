# amplifier-bundle-workgraph

Integrates [workgraph](https://github.com/graphwork/workgraph) with [Amplifier](https://github.com/microsoft/amplifier) for dependency-aware task coordination.

## Quick Start

```bash
# Run the setup script (does everything in one command)
curl -sL https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/setup.sh | bash

# Or from a local clone:
./setup.sh
```

That's it! The setup script will:
1. Add the workgraph bundle to Amplifier
2. Install the Amplifier executor into `.workgraph/executors/`
3. Set Amplifier as the default executor
4. Install a validation hook for setup health checks

## What This Does

Two integration directions:

**Amplifier -> Workgraph**: Add workgraph awareness to your Amplifier sessions. Agents automatically detect when a task has non-linear dependencies and decompose it into a workgraph for parallel execution.

**Workgraph -> Amplifier**: Install the Amplifier executor so workgraph's service daemon spawns full Amplifier sessions for each task -- bringing Amplifier's entire ecosystem (bundles, tools, recipes, multi-agent delegation) to each workgraph task.

## Troubleshooting

### "wg: command not found"

Install workgraph:
```bash
# See https://github.com/graphwork/workgraph for installation
```

### "Executor not installed" or "version mismatch"

Run the setup script again:
```bash
./setup.sh
# Or to check status without modifying:
./setup.sh --check
```

### "Empty prompt error" from amplifier-run.sh

This usually means the executor config has the wrong type. Verify your `.workgraph/executors/amplifier.toml` has:
```toml
type = "claude"
```
(The `type = "claude"` tells workgraph to pipe the prompt via stdin - it's not about using Claude models.)

### Agent doesn't know wg commands

Make sure you're using the workgraph behavior. Start your session with:
```bash
amplifier run -B workgraph
```

Or add the behavior to your bundle configuration.

### Provider patches lost after amplifier update

If you use a patched `provider-openai`, run the sync script after any `amplifier update`:
```bash
./scripts/sync-provider-cache.sh
```

### Why does the TOML say `type = "claude"`?

Workgraph uses different input modes per executor type. The `claude` type tells workgraph to pipe the rendered prompt template via stdin. This is the only type that passes the full task context to the executor. It's not about using Claude models - it works with any provider.

## Configuration

### Executor Timeout

Default: 600 seconds (10 minutes). Adjust in `amplifier.toml`:

```toml
[executor]
timeout = 1200  # 20 minutes for larger tasks
```

### Max Parallel Agents

Set in your `.workgraph/config.toml`:

```toml
[coordinator]
max_agents = 4        # Up to 4 Amplifier sessions running in parallel
executor = "amplifier"
```

### Using a Custom Bundle

To use a specific Amplifier bundle for executor sessions, modify the args in `amplifier.toml`:

```toml
args = ["run", "--mode", "single", "--output-format", "json", "-B", "your-bundle-name"]
```

## Validating Your Setup

```bash
# Check setup health without modifying anything
./setup.sh --check

# Run integration tests
./tests/test_integration.sh --quick
```

## How It Works

When workgraph's service daemon dispatches a task:

1. Workgraph renders the prompt template with task context (ID, title, description, dependency artifacts)
2. Spawns `amplifier run --mode single --output-format json`
3. Pipes the rendered prompt via stdin
4. Amplifier session does the work, calling `wg log`, `wg artifact`, `wg done`/`wg fail`
5. Workgraph detects completion and dispatches newly-unblocked tasks

The executor config is a standard workgraph TOML file at `.workgraph/executors/amplifier.toml`. Template variables (`{{task_id}}`, `{{task_title}}`, etc.) are replaced at spawn time.

## Architecture

```
User
  |
  v
Amplifier Session (with workgraph behavior)
  |
  |--> detects complex task
  |--> wg init / wg add (builds task graph)
  |--> wg service start (launches daemon)
  |
  v
Workgraph Service Daemon
  |
  |--> dispatches ready tasks
  |--> spawns Amplifier executor for each
  |
  +---> Amplifier Session (task A) ---> wg done task-a
  +---> Amplifier Session (task B) ---> wg done task-b
  +---> Amplifier Session (task C) ---> wg done task-c
  |
  |--> detects completions, unblocks dependents
  |--> spawns next wave
  v
All tasks done --> reports back to user
```

## What's Included

```
amplifier-bundle-workgraph/
  bundle.md                     # Root bundle definition
  setup.sh                      # One-command setup (recommended)
  behaviors/
    workgraph.yaml              # Behavior: adds workgraph context to agents
  context/
    workgraph-guide.md          # When/how to use workgraph (loaded into agent context)
    wg-executor-protocol.md     # Protocol for agents spawned by workgraph
  agents/
    workgraph-planner.md        # Specialized agent for task decomposition
  executor/
    amplifier.toml              # Workgraph executor config for Amplifier
    amplifier-run.sh            # Wrapper script that bridges stdin to positional arg
    install.sh                  # Legacy install script (setup.sh is preferred)
  hooks/
    workgraph-setup/            # SessionStart hook for setup validation
  scripts/
    sync-provider-cache.sh      # Sync provider patches after amplifier update
  tests/
    test_integration.sh         # Integration tests
```

## Manual Installation (Advanced)

If you prefer piece-by-piece control, here are the manual steps:

### Step 1: Add the bundle to Amplifier

```bash
amplifier bundle add git+https://github.com/graphwork/amplifier-bundle-workgraph
```

### Step 2: Install the executor

```bash
# Initialize workgraph if needed
wg init

# Copy executor files
cp executor/amplifier.toml .workgraph/executors/
cp executor/amplifier-run.sh .workgraph/executors/
chmod +x .workgraph/executors/amplifier-run.sh
```

### Step 3: Set as default executor

```bash
wg config --coordinator-executor amplifier
```

## Testing

```bash
# Quick tests (no LLM calls, validates structure and config)
./tests/test_integration.sh --quick

# Full tests (spawns a real Amplifier session for a trivial task)
./tests/test_integration.sh
```
