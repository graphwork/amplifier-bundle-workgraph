# Multi-Provider CLI Workflow Design

**Status:** Proposal (iteration 0)
**Date:** 2026-02-25
**Based on:** MULTI_PROVIDER_REVIEW.md test results, current Amplifier CLI

---

## Problem Statement

Amplifier supports configuring multiple LLM providers, but the UX has gaps:

1. **`--provider` uses module shorthand, not user-defined names.** A provider configured as `name: openrouter` must be selected with `--provider openai`, which is confusing.
2. **Same-module providers can't coexist.** Two `provider-openai` instances (e.g., direct OpenAI + OpenRouter) overwrite each other because the module hardcodes `name="openai"` in `coordinator.mount()`.
3. **`provider current` reports config-time priority, not runtime health.** It shows "anthropic" even when that provider fails to load.
4. **No way to list configured (as opposed to available) providers.** `amplifier provider list` shows all known modules, not which ones the user has set up.

---

## Current State

### CLI Commands

| Command | Purpose |
|---------|---------|
| `amplifier provider list` | List all **available** provider modules |
| `amplifier provider use <id>` | Configure a provider (interactive wizard) |
| `amplifier provider current` | Show the default provider |
| `amplifier provider reset` | Remove provider override |
| `amplifier provider models [id]` | List models for a provider |
| `amplifier provider install [ids]` | Download provider modules |
| `amplifier run --provider <id> --model <m>` | Per-session provider override |

### Config Structure (`~/.amplifier/settings.yaml`)

```yaml
config:
  providers:
    - module: provider-anthropic
      config:
        api_key: sk-ant-...
        default_model: claude-sonnet-4-20250514
        priority: 1        # lower = higher precedence
    - name: openrouter      # cosmetic only — not used by --provider
      module: provider-openai
      config:
        api_key: sk-or-v1-...
        base_url: https://openrouter.ai/api/v1
        default_model: minimax/minimax-m2.5
        priority: 10
```

### Provider Selection at Runtime

1. All providers in `config.providers[]` are loaded (partial failure tolerated)
2. Lowest-priority-number provider becomes default
3. `--provider <shorthand>` sets that provider to priority 0 for the session
4. `<shorthand>` is the module's hardcoded mount name (e.g., `openai`, `anthropic`)

---

## Proposed Design

### Phase 1: Named Provider Instances (Short-term)

#### Goal
Let `--provider` match the `name:` field in settings.yaml, falling back to module shorthand for backward compatibility.

#### Config Changes

Add a required `name:` field to each provider entry. If omitted, it defaults to the module shorthand (e.g., `provider-openai` → `openai`).

```yaml
config:
  providers:
    - name: anthropic          # explicit name (default = module shorthand)
      module: provider-anthropic
      config:
        api_key: sk-ant-...
        default_model: claude-sonnet-4-20250514
        priority: 1

    - name: openrouter         # user-chosen name — usable with --provider
      module: provider-openai
      config:
        api_key: sk-or-v1-...
        base_url: https://openrouter.ai/api/v1
        default_model: minimax/minimax-m2.5
        priority: 10
```

#### Mount Name Change

The `mount()` call in each provider module should use the config-supplied name:

```python
# Before (hardcoded):
await coordinator.mount("providers", provider, name="openai")

# After (config-driven):
mount_name = config.get("_instance_name", "openai")
await coordinator.mount("providers", provider, name=mount_name)
```

The orchestrator passes `_instance_name` (from the `name:` field) into each provider's config before calling `mount()`.

#### CLI Behavior

```bash
# Select by user-defined name (new behavior)
amplifier run --provider openrouter "Your prompt"

# Select by module shorthand (backward compat — matches first instance)
amplifier run --provider openai "Your prompt"

# Resolution order:
# 1. Exact match on name: field
# 2. Exact match on module shorthand (provider-<X> → <X>)
# 3. Error: "Provider '<name>' not configured"
```

#### New Commands

**`amplifier provider configured`** — List the user's configured providers with runtime health:

```
$ amplifier provider configured
                    Configured Providers
┏━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━┓
┃ Name        ┃ Module            ┃ Model    ┃ Priority ┃ Status ┃
┡━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━┩
│ anthropic   │ provider-anthropic│ claude-… │ 1        │ ✗ no key │
│ openrouter  │ provider-openai   │ minimax… │ 10       │ ✓ ok     │
└─────────────┴───────────────────┴──────────┴──────────┴────────┘
```

**`amplifier provider add <module> --name <name>`** — Add a second provider interactively:

```bash
# Add OpenRouter as a named instance of the openai module
amplifier provider add openai --name openrouter \
  --config base_url=https://openrouter.ai/api/v1 \
  --config api_key=sk-or-v1-... \
  --model minimax/minimax-m2.5

# Add a second Anthropic endpoint
amplifier provider add anthropic --name anthropic-eu \
  --config base_url=https://eu.api.anthropic.com
```

**`amplifier provider remove <name>`** — Remove a configured provider:

```bash
amplifier provider remove openrouter
```

#### Updated `provider current`

Show runtime health alongside config priority:

```
$ amplifier provider current
Active provider: openrouter
  Name: openrouter
  Module: provider-openai
  Model: minimax/minimax-m2.5
  Priority: 10 (effective: 1 — higher-priority providers failed)
  Status: ✓ loaded

Other configured providers:
  anthropic (provider-anthropic): ✗ no API key
```

---

### Phase 2: Per-Task Provider Override (Medium-term)

#### Goal
Allow workgraph tasks and project configs to specify which provider to use, without changing the global default.

#### Project-Level Override (`.amplifier/settings.yaml`)

```yaml
config:
  provider: openrouter       # project default — overrides global priority
```

#### Workgraph Task Override

Tasks can specify a preferred provider in the description or via metadata:

```bash
wg add "Translate docs" --metadata provider=openrouter
```

The Amplifier executor reads this metadata and adds `--provider <name>` to the `amplifier run` invocation.

#### Environment Variable Override

```bash
AMPLIFIER_PROVIDER=openrouter amplifier run "Your prompt"
```

#### Priority Chain (highest to lowest)

1. `amplifier run --provider <name>` (CLI flag)
2. `AMPLIFIER_PROVIDER` environment variable
3. Project `.amplifier/settings.yaml` `config.provider` field
4. Workgraph task metadata `provider=<name>`
5. Global `~/.amplifier/settings.yaml` priority numbers

---

### Phase 3: Same-Module Multi-Instance (Long-term)

#### Goal
Allow two instances of the same module (e.g., direct OpenAI + OpenRouter, both using `provider-openai`) to coexist and be independently selectable.

#### Technical Change

Currently, `coordinator.mount("providers", provider, name="openai")` uses a hardcoded name, so a second mount with the same name overwrites the first. The fix:

1. The orchestrator assigns each provider entry a unique mount name from its `name:` field
2. Provider modules accept the mount name as a config parameter (`_instance_name`)
3. The `--provider` flag resolves against mount names, not module shorthands

This is already described in Phase 1's mount change. The additional work for Phase 3 is:

- **Module isolation:** Each instance gets its own config, API client, and state
- **Model listing:** `amplifier provider models openrouter` returns models available via that specific instance
- **Deduplication:** If a user has both direct OpenAI and OpenRouter, model lists should indicate which instance(s) can serve each model

#### Config Example

```yaml
config:
  providers:
    - name: openai-direct
      module: provider-openai
      config:
        api_key: sk-...            # OpenAI key
        default_model: gpt-5.1
        priority: 1

    - name: openrouter
      module: provider-openai
      config:
        api_key: sk-or-v1-...     # OpenRouter key
        base_url: https://openrouter.ai/api/v1
        default_model: anthropic/claude-sonnet-4
        priority: 10

    - name: anthropic
      module: provider-anthropic
      config:
        api_key: sk-ant-...
        default_model: claude-sonnet-4-20250514
        priority: 5
```

```bash
amplifier run --provider openai-direct "prompt"   # → OpenAI
amplifier run --provider openrouter "prompt"       # → OpenRouter
amplifier run --provider anthropic "prompt"        # → Anthropic
amplifier run "prompt"                             # → openai-direct (priority 1)
```

---

## Migration & Backward Compatibility

| Scenario | Behavior |
|----------|----------|
| No `name:` field in settings.yaml | Defaults to module shorthand (e.g., `openai`) |
| `--provider openai` with named instance `openrouter` | Falls back to module shorthand match → finds `openrouter` (uses `provider-openai`) |
| Existing scripts using `--provider anthropic` | Continue to work — module shorthand is always a valid selector |
| Two unnamed instances of same module | Second overwrites first (current behavior, with deprecation warning) |

---

## Summary of New/Changed Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `amplifier provider configured` | 1 | List configured providers with health status |
| `amplifier provider add <module> --name <name>` | 1 | Add a named provider instance |
| `amplifier provider remove <name>` | 1 | Remove a configured provider |
| `amplifier run --provider <name>` | 1 | Match `name:` field (fallback to module shorthand) |
| `amplifier provider current` (updated) | 1 | Show runtime health, not just config priority |
| `AMPLIFIER_PROVIDER` env var | 2 | Environment-based provider override |
| Project `config.provider` field | 2 | Per-project default provider |
| `wg add --metadata provider=<name>` | 2 | Per-task provider override via workgraph |

---

## Open Questions

1. **Should `amplifier provider use` be updated to support `--name`?** Currently it configures by module ID. Adding `--name` would let users name the instance during initial setup.
2. **Should `provider configured` require loading providers (slow) or just read config (fast)?** A `--check` flag could opt into the slow health check.
3. **How should `amplifier init` handle multi-provider?** Currently it sets up one provider. Could offer "Add another provider?" at the end.
4. **Should priority be replaced with explicit `default: true`?** Numeric priority is flexible but less intuitive than a boolean default flag.
