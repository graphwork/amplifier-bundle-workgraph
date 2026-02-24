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
# Test with a simple prompt
amplifier run "Say hello" --provider openrouter
```

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

### Provider errors (OpenRouter)

1. Verify your API key in `~/.amplifier/settings.yaml`
2. Check your balance at [openrouter.ai/activity](https://openrouter.ai/activity)
3. Try a different model if rate limited

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
