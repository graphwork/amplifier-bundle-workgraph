# Workgraph Integration Guide

You have access to [workgraph](https://github.com/graphwork/workgraph) (`wg`) for dependency-aware task coordination.

## When to Use Workgraph

**Use workgraph when** the task has non-linear dependencies -- multiple workstreams that can run in parallel but have ordering constraints between them.

| Task Shape | Approach |
|---|---|
| "Fix this bug" | Normal single-agent work, no workgraph |
| "Add a feature to file X" | Normal work, maybe a recipe |
| "Refactor the auth system into 3 services" | **Non-linear deps** -- use workgraph |
| "Build the MVP from this spec" | **Complex parallel work** -- use workgraph |
| "Review and update all API endpoints" | **Independent batch** -- use workgraph |

**Detection heuristics** -- consider workgraph when:
- Task naturally decomposes into 4+ subtasks
- Some subtasks can run in parallel
- Subtasks have dependencies (B needs A's output)
- Different subtasks need different skills/approaches
- Task would benefit from progress tracking across branches

**Do NOT use workgraph for**:
- Simple sequential tasks (use recipes instead)
- Single-file changes
- Tasks with no parallelism opportunity

## Quick Start

```bash
# Initialize workgraph in a project
wg init

# Add tasks with dependencies
wg add "Design API schema" --skill architecture
wg add "Build user service" --blocked-by design-api-schema --skill rust
wg add "Build auth service" --blocked-by design-api-schema --skill rust
wg add "Integration tests" --blocked-by build-user-service --blocked-by build-auth-service --skill testing

# Check status
wg status
wg ready          # Show tasks ready to work on
wg viz            # ASCII dependency graph

# Start the service daemon for parallel execution
wg service start --max-agents 3

# Monitor progress
wg agents         # Show running agents
wg bottlenecks    # What's blocking the most work?
wg forecast       # Completion estimate
```

## Core CLI Commands

### Task Management

| Command | Description |
|---------|-------------|
| `wg init` | Initialize `.workgraph/` in current directory |
| `wg add <TITLE>` | Add task (`--blocked-by`, `--skill`, `--model`, `--verify`) |
| `wg edit <ID>` | Modify task fields |
| `wg done <ID>` | Mark complete (unblocks dependents) |
| `wg fail <ID> --reason "..."` | Mark failed |
| `wg claim <ID>` | Claim task (status -> in-progress) |
| `wg log <ID> <MSG>` | Add progress note |
| `wg artifact <ID> <PATH>` | Record produced file |
| `wg retry <ID>` | Reset failed -> open |

### Querying

| Command | Description |
|---------|-------------|
| `wg ready` | Tasks ready to work on now |
| `wg list` | All tasks (filter with `--status`) |
| `wg show <ID>` | Full task details |
| `wg status` | One-screen overview |
| `wg blocked <ID>` | What blocks this task? |
| `wg why-blocked <ID>` | Transitive blocker chain |
| `wg impact <ID>` | What depends on this task? |
| `wg context <ID>` | Available context from completed deps |

### Analysis

| Command | Description |
|---------|-------------|
| `wg viz` | Dependency graph (ASCII/DOT/Mermaid) |
| `wg bottlenecks` | Tasks blocking the most work |
| `wg critical-path` | Longest dependency chain |
| `wg forecast` | Project completion estimate |
| `wg velocity` | Task completion rate over time |
| `wg analyze` | Comprehensive health report |
| `wg coordinate` | Parallel execution opportunities |

### Service Daemon

| Command | Description |
|---------|-------------|
| `wg service start` | Start background daemon |
| `wg service stop` | Stop daemon |
| `wg service status` | Daemon info |
| `wg service pause` | Pause coordinator (no new spawns) |
| `wg service resume` | Resume coordinator |
| `wg spawn <ID>` | Manually spawn agent for a task |
| `wg agents` | List running agents |
| `wg kill <AGENT>` | Kill an agent |

## Task Lifecycle

```
Open --> InProgress --> Done
  |         |
  |         +--> Failed --> (retry) --> Open
  |
  +--> Blocked (computed: has unresolved blocked_by)
```

- Tasks auto-unblock when all `blocked_by` dependencies reach `Done`
- The service daemon auto-spawns agents for newly-ready tasks
- Loop edges enable cyclic workflows (write -> review -> revise) with iteration caps

## Task Fields

Key fields when creating tasks:

- **`--blocked-by <ID>`** -- Dependency (this task waits for that one)
- **`--skill <NAME>`** -- Required capability (for agent matching)
- **`--model <NAME>`** -- Model override (haiku/sonnet/opus)
- **`--verify <CRITERIA>`** -- Verification criteria (enables review)
- **`--loops-to <ID>`** -- Create cyclic workflow edge
- **`--tag <TAG>`** -- Categorization tag

## Decomposition Patterns

When decomposing a complex task, use the **workgraph-planner** agent:

```
delegate to workgraph-planner: "Decompose this task into a workgraph: <description>"
```

The planner will:
1. Analyze the task for parallelizable branches
2. Identify dependencies between subtasks
3. Create the task graph with `wg add` commands
4. Set appropriate skills and verification criteria
5. Optionally start the service daemon

### Common Decomposition Shapes

**Fan-out / Fan-in**:
```
        design
       /   |   \
    svc-A svc-B svc-C
       \   |   /
      integration
```

**Pipeline with parallel branches**:
```
    analyze --> design --> impl-core
                           |
                      +----+----+
                      |         |
                   impl-A    impl-B
                      |         |
                      +----+----+
                           |
                         test
```

**Iterative (loop edges)**:
```
    write --> review --> revise (loops back to review, max 3 iterations)
```

## Configuration

`.workgraph/config.toml`:
```toml
[coordinator]
max_agents = 4        # Max parallel agents
executor = "amplifier" # Default executor (after installing Amplifier executor)

[project]
name = "My Project"
description = "..."
```

## Amplifier Executor

To let workgraph spawn Amplifier sessions, install the executor:

```bash
# From the amplifier-bundle-workgraph directory
./executor/install.sh

# Or manually copy
cp executor/amplifier.toml .workgraph/executors/amplifier.toml

# Set as default
wg config coordinator.executor amplifier
```

Then `wg service start` will use Amplifier for all spawned agents.
