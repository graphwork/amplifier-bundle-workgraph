# amplifier-bundle-workgraph

Integrates [workgraph](https://github.com/graphwork/workgraph) with [Amplifier](https://github.com/microsoft/amplifier) for dependency-aware task coordination.

## What This Does

Two integration directions:

**Amplifier -> Workgraph**: Add workgraph awareness to your Amplifier sessions. Agents automatically detect when a task has non-linear dependencies and decompose it into a workgraph for parallel execution.

**Workgraph -> Amplifier**: Install the Amplifier executor so workgraph's service daemon spawns full Amplifier sessions for each task -- bringing Amplifier's entire ecosystem (bundles, tools, recipes, multi-agent delegation) to each workgraph task.

## Prerequisites

- [workgraph](https://github.com/graphwork/workgraph) (`wg`) installed
- [Amplifier](https://github.com/microsoft/amplifier) installed

## Quick Start

### Adding Workgraph to Amplifier

Add the workgraph behavior to your bundle:

```yaml
# In your bundle.md or behavior YAML
includes:
  - git+https://github.com/graphwork/amplifier-bundle-workgraph#subdirectory=behaviors/workgraph.yaml
```

Or install directly:

```bash
amplifier bundle add git+https://github.com/graphwork/amplifier-bundle-workgraph
```

Then in any Amplifier session, the agent will know when and how to use workgraph:

```
you> "Refactor the auth system: split into OAuth, JWT, and session services.
      Update all callers. Full test coverage."

amplifier> [detects non-linear dependencies, decomposes into workgraph]
           "I've broken this into 7 tasks with 3 parallel branches..."
```

### Using Amplifier as a Workgraph Executor

Install the executor into your workgraph project:

```bash
# From the bundle directory
./executor/install.sh /path/to/your/project

# Or manually
cp executor/amplifier.toml /path/to/your/project/.workgraph/executors/

# Set as default executor
cd /path/to/your/project
wg config --coordinator-executor amplifier
```

Now `wg service start` will use Amplifier for all spawned agents. Each task gets a full Amplifier session with tools, delegation, and the full bundle ecosystem.

## What's Included

```
amplifier-bundle-workgraph/
  bundle.md                     # Root bundle definition
  behaviors/
    workgraph.yaml              # Behavior: adds workgraph context to agents
  context/
    workgraph-guide.md          # When/how to use workgraph (loaded into agent context)
    wg-executor-protocol.md     # Protocol for agents spawned by workgraph
  agents/
    workgraph-planner.md        # Specialized agent for task decomposition
  executor/
    amplifier.toml              # Workgraph executor config for Amplifier
    install.sh                  # Install executor into a workgraph project
  tests/
    test_integration.sh         # Integration tests
```

## How the Executor Works

When workgraph's service daemon dispatches a task:

1. Workgraph renders the prompt template with task context (ID, title, description, dependency artifacts)
2. Spawns `amplifier run --mode single --output-format json`
3. Pipes the rendered prompt via stdin
4. Amplifier session does the work, calling `wg log`, `wg artifact`, `wg done`/`wg fail`
5. Workgraph detects completion and dispatches newly-unblocked tasks

The executor config is a standard workgraph TOML file at `.workgraph/executors/amplifier.toml`. Template variables (`{{task_id}}`, `{{task_title}}`, etc.) are replaced at spawn time.

## Testing

```bash
# Quick tests (no LLM calls, validates structure and config)
./tests/test_integration.sh --quick

# Full tests (spawns a real Amplifier session for a trivial task)
./tests/test_integration.sh
```

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
