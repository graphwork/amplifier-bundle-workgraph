# Amplifier + Workgraph: Zero to Working

This is the definitive guide to get Amplifier and Workgraph running together in under 10 minutes.

---

## Step 1: Install Amplifier and Workgraph

### Install Amplifier

```bash
# Install via uv (recommended)
uv tool install git+https://github.com/microsoft/amplifier

# Verify
amplifier --version
```

### Install Workgraph

```bash
# Requires Rust toolchain (https://rustup.rs)
cargo install workgraph

# Verify
wg --version
```

---

## Step 2: Configure Amplifier with OpenRouter

### Run the Setup Wizard

```bash
amplifier init
```

This starts an interactive wizard. When prompted:
1. Select your preferred provider
2. Enter your API key

### Configure OpenRouter Manually

If you prefer manual configuration or need to add OpenRouter as a second provider:

**1. Get an API key** from [openrouter.ai/keys](https://openrouter.ai/keys)

**2. Add to your settings** (`~/.amplifier/settings.yaml`):

```yaml
config:
  providers:
    - name: openrouter
      module: provider-openai
      config:
        api_key: sk-or-v1-YOUR-OPENROUTER-KEY
        base_url: https://openrouter.ai/api/v1
        default_model: anthropic/claude-3.5-sonnet
        priority: 1
```

**3. Verify the configuration:**

```bash
# IMPORTANT: Use --provider openai, not --provider openrouter
# The OpenRouter configuration is mounted internally as "openai"
amplifier run "Say hello" --provider openai
```

---

### Important: Provider Name

The OpenRouter configuration is mounted internally as "openai", not "openrouter".
Use `--provider openai` when running Amplifier:

```bash
amplifier run "Your prompt" --provider openai
```

---

### Advanced: OpenRouter-Specific Options

When using OpenRouter, the following features are automatically configured.
You can override these in your settings:

| Option | Default | Description |
|--------|---------|-------------|
| `enable_native_tools` | true | Enable OpenAI apply_patch_call tool format |
| `enable_reasoning_replay` | true | Enable reasoning state preservation |
| `enable_store` | false | Enable OpenAI Store feature |
| `enable_background` | false | Enable background/async mode |

Example to disable native tools if your model doesn't support them:

```yaml
config:
  providers:
    - name: openrouter
      module: provider-openai
      config:
        api_key: sk-or-v1-YOUR-OPENROUTER-KEY
        base_url: https://openrouter.ai/api/v1
        default_model: anthropic/claude-3.5-sonnet
        enable_native_tools: false
        enable_reasoning_replay: false
```

---

## Step 2b: Multi-Provider Configuration

Amplifier supports multiple providers simultaneously. This allows you to switch
between providers per-session using `--provider`, while keeping a default for
everyday use.

### How It Works

- Providers are listed under `config.providers[]` in `~/.amplifier/settings.yaml`
- The `priority` field controls which provider is active by default (lower = higher precedence)
- `amplifier run --provider <name>` temporarily overrides the default for that session
- The `<name>` is the **module shorthand** (e.g., `anthropic`, `openai`), not the `name:` field in YAML

### Example: Anthropic + OpenRouter

```yaml
# ~/.amplifier/settings.yaml
config:
  providers:
    # Primary provider — direct Anthropic (priority 1 = default)
    - module: provider-anthropic
      source: git+https://github.com/microsoft/amplifier-module-provider-anthropic@main
      config:
        api_key: ${ANTHROPIC_API_KEY}   # or hardcode your key
        base_url: https://api.anthropic.com
        default_model: claude-sonnet-4-20250514
        priority: 1

    # Secondary provider — OpenRouter (priority 10 = fallback)
    - name: openrouter
      module: provider-openai
      source: git+https://github.com/microsoft/amplifier-module-provider-openai@main
      config:
        api_key: sk-or-v1-YOUR-OPENROUTER-KEY
        base_url: https://openrouter.ai/api/v1
        default_model: anthropic/claude-3.5-sonnet
        priority: 10
```

### Switching Providers

```bash
# Use default provider (anthropic, priority 1)
amplifier run "Your prompt"

# Explicitly select Anthropic
amplifier run "Your prompt" --provider anthropic

# Switch to OpenRouter for this session
amplifier run "Your prompt" --provider openai

# OpenRouter with a specific model
amplifier run "Your prompt" --provider openai --model deepseek/deepseek-chat-v3-0324
```

### Checking Active Provider

```bash
# Show which provider is active by default
amplifier provider current
```

### Changing the Default Provider

```bash
# Make OpenRouter the default (sets priority 1, demotes others to 10)
amplifier provider use openai --model anthropic/claude-3.5-sonnet

# Switch back to Anthropic as default
amplifier provider use anthropic --model claude-sonnet-4-20250514
```

### Important: Provider Names vs Module IDs

The `--provider` flag uses the **module shorthand**, not the `name:` field:

| Module | `--provider` value | Notes |
|--------|-------------------|-------|
| `provider-anthropic` | `anthropic` | Direct Anthropic API |
| `provider-openai` | `openai` | OpenAI or OpenAI-compatible (e.g., OpenRouter) |
| `provider-azure-openai` | `azure-openai` | Azure OpenAI |
| `provider-gemini` | `gemini` | Google Gemini |
| `provider-ollama` | `ollama` | Local Ollama |

**Limitation**: You cannot have two providers with the same module and select between them
via `--provider`. For example, direct OpenAI + OpenRouter both use `provider-openai`, so
`--provider openai` would activate whichever has higher priority. Use different priority
values and `amplifier provider use` to switch the default.

---

## Step 3: One-Command Integration

Run the setup script from the amplifier-bundle-workgraph repository:

```bash
# From a local clone:
git clone https://github.com/graphwork/amplifier-bundle-workgraph.git
cd amplifier-bundle-workgraph
./setup.sh

# Or via curl (from any directory):
curl -sL https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/setup.sh | bash
```

### What Setup Does

The script automatically:
1. ✅ Verifies `amplifier` and `wg` are installed
2. ✅ Adds the workgraph bundle to Amplifier
3. ✅ Installs the Amplifier executor into `.workgraph/executors/`
4. ✅ Sets Amplifier as the default executor
5. ✅ Installs the validation hook

### Verify Setup Health

```bash
./setup.sh --check
```

Expected output:
```
=== Amplifier + Workgraph Setup Check ===
  amplifier: /path/to/amplifier ✓
  wg: /path/to/wg ✓
  workgraph bundle: installed ✓
  executor: v0.2.0 ✓
  amplifier-run.sh: executable ✓
  coordinator executor: amplifier ✓
  validation hook: installed ✓

All checks passed ✓
```

---

## Step 4: Your First Task

### Initialize Workgraph in Your Project

```bash
cd your-project-directory
wg init
```

### Add Tasks with Dependencies

Create a simple task graph with parallel work:

```bash
# Add independent tasks that can run in parallel
wg add "Research best practices" --skill research
wg add "Write documentation" --skill writing

# Add a task that waits for both to complete
wg add "Review and merge" --blocked-by research-best-practices --blocked-by write-documentation
```

### Start the Service Daemon

```bash
# Start with up to 3 parallel agents
wg service start --max-agents 3
```

The daemon will:
- Spawn Amplifier sessions for ready tasks automatically
- Monitor progress and unblock dependent tasks
- Continue until all tasks are complete

### Monitor Progress

In another terminal:

```bash
# See all tasks
wg status

# See what's ready to work on
wg ready

# Visualize the dependency graph
wg viz
```

### Complete a Task

When a task is done, mark it complete:

```bash
wg done <task-id>
```

This automatically unblocks any tasks waiting on it.

---

## Quick Reference

```bash
# === ONE-TIME SETUP ===
uv tool install git+https://github.com/microsoft/amplifier
cargo install workgraph
amplifier init  # Follow the wizard to configure your provider

# === INTEGRATION ===
git clone https://github.com/graphwork/amplifier-bundle-workgraph.git
cd amplifier-bundle-workgraph
./setup.sh

# === NEW PROJECT ===
cd my-project
wg init
wg add "First task" --skill python
wg add "Second task" --blocked-by first-task
wg service start --max-agents 3

# === MONITOR ===
wg status
wg ready
wg viz
```

---

## Troubleshooting

### "wg: command not found"

Workgraph isn't in your PATH:

```bash
cargo install workgraph
# Ensure ~/.cargo/bin is in your PATH
```

### "Empty prompt error" from amplifier-run.sh

The executor config has the wrong type. Verify `.workgraph/executors/amplifier.toml`:

```toml
type = "claude"
```

### "Executor not installed" or version mismatch

Run the setup script again:

```bash
./setup.sh
```

### "Provider 'openrouter' not configured"

You're using `--provider openrouter` but the provider is mounted as "openai".
Use `--provider openai` instead:

```bash
amplifier run "Your prompt" --provider openai
```

### Provider errors (OpenRouter)

1. Verify your API key in `~/.amplifier/settings.yaml`
2. Check your balance at [openrouter.ai/activity](https://openrouter.ai/activity)
3. Try a different model if rate limited

### "No API key found for <provider>"

Both the `api_key` config field and the environment variable (e.g., `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`) are missing. Add the key to your settings.yaml or export the env var:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
# or add api_key: sk-ant-... under the provider's config in settings.yaml
```

If one provider fails but another succeeds, Amplifier shows a "Partial provider failure"
warning and continues with the available provider.

### Agent doesn't know wg commands

Make sure you're using the workgraph behavior:

```bash
amplifier run -B workgraph
```

---

## Next Steps

| Goal | Action |
|------|--------|
| Learn workgraph commands | See [workgraph-guide.md](../context/workgraph-guide.md) |
| Decompose complex tasks | Use the `workgraph-planner` agent |
| Customize behavior | Edit `.workgraph/config.toml` |
| Run integration tests | `./tests/test_integration.sh` |
