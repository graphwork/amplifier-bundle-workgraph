---
bundle:
  name: workgraph
  version: 0.2.0
  description: "Workgraph integration for Amplifier -- dependency-aware task graph coordination"
includes:
  - bundle: git+https://github.com/microsoft/amplifier-foundation@main
  - bundle: workgraph:behaviors/workgraph
---

# Workgraph Integration

Integrates [workgraph](https://github.com/graphwork/workgraph) with Amplifier for dependency-aware task coordination.

## What This Provides

- **Task graph awareness** -- Agents understand when to decompose work into dependency graphs
- **`wg` CLI integration** -- Agents can create, manage, and execute workgraph tasks
- **Workgraph planner agent** -- Specialized agent for task decomposition
- **Amplifier executor** -- Lets workgraph spawn Amplifier sessions for task execution

## Two Integration Directions

### Amplifier -> Workgraph (this bundle)

Add workgraph capabilities to your Amplifier sessions. Agents automatically detect
when a task has non-linear dependencies and decompose it into a workgraph for
parallel execution.

### Workgraph -> Amplifier (executor)

Install the Amplifier executor so workgraph's service daemon can spawn full
Amplifier sessions for each task. See `executor/` directory.
