# OpenRouter Provider Design

This document outlines the design for making OpenRouter a first-class provider in Amplifier.

## Overview

OpenRouter is an AI model aggregation service that provides access to 100+ models from various providers through a unified OpenAI-compatible API. This design enables users to configure OpenRouter via `amplifier provider use openrouter` with automatic model listing and proper feature flag handling.

## Research Findings

### 1. How `amplifier provider use` Works

The `amplifier provider use` CLI command allows users to configure providers. Current supported providers:
- `anthropic` - Anthropic models
- `openai` - OpenAI models
- `azure-openai` - Azure OpenAI deployment
- `ollama` - Local Ollama models

The command accepts flags like `--model`, `--deployment`, `--endpoint`, `--use-azure-cli` for provider-specific configuration.

### 2. How Existing Providers Register

Providers are registered in amplifier-foundation through:
1. **Provider YAML files** in `providers/` directory (e.g., `providers/openai-gpt.yaml`)
2. **Bundle composition** - provider YAML files are included in bundles via the `includes` directive
3. **Provider configuration** - each provider YAML specifies the module, source, and default config

Example provider YAML structure:
```yaml
bundle:
  name: provider-openai-gpt
  version: 1.0.0
  description: OpenAI GPT provider

providers:
  - module: provider-openai
    source: git+https://github.com/microsoft/amplifier-module-provider-openai@main
    config:
      default_model: gpt-5.2
      debug: true
```

### 3. Provider-OpenAI Config Flags (PR #17)

The provider-openai module now supports per-feature config flags for custom endpoint compatibility:

| Flag | Purpose | Default (no base_url) | Default (with base_url) |
|------|---------|----------------------|------------------------|
| `enable_native_tools` | tools, web_search_preview, etc. | true | false |
| `enable_reasoning_replay` | encrypted_content, reasoning items | true | false |
| `enable_store` | store param, previous_response_id | true | false |
| `enable_background` | background mode for deep research | true | false |

These flags auto-detect when a custom endpoint is used (via base_url) and disable OpenAI-specific features that may not be supported.

---

## Design

### Config Structure

Create a new provider YAML file: `providers/openrouter.yaml`

```yaml
bundle:
  name: provider-openrouter
  version: 1.0.0
  description: OpenRouter provider - unified API for 100+ models

providers:
  - module: provider-openai
    source: git+https://github.com/microsoft/amplifier-module-provider-openai@main
    config:
      base_url: https://openrouter.ai/api/v1
      default_model: deepseek/deepseek-chat-v3-0324
      # OpenRouter-specific flags - most OpenAI features work
      enable_native_tools: true
      enable_reasoning_replay: true
      enable_store: false    # OpenRouter doesn't support store
      enable_background: false
```

#### Config Flag Justification

| Flag | Value | Reason |
|------|-------|--------|
| `enable_native_tools` | true | OpenRouter supports tools/callouts |
| `enable_reasoning_replay` | true | Most models support reasoning |
| `enable_store` | false | OpenRouter doesn't support the store parameter |
| `enable_background` | false | OpenRouter doesn't support background mode |

### CLI Flow: `amplifier provider use openrouter`

```
$ amplifier provider use openrouter --model anthropic/claude-3.5-sonnet

Configuring OpenRouter provider...
API Key: (reads from OPENROUTER_API_KEY env or prompts)
Model: anthropic/claude-3.5-sonnet (default: deepseek/deepseek-chat-v3-0324)

Provider configured successfully!
  base_url: https://openrouter.ai/api/v1
  model: anthropic/claude-3.5-sonnet
  enable_native_tools: true
  enable_reasoning_replay: true
  enable_store: false
  enable_background: false
```

#### Non-interactive mode (`--yes` / `-y`)

```bash
# Use environment variable
export OPENROUTER_API_KEY=sk-or-...
amplifier provider use openrouter --model anthropic/claude-3.5-sonnet -y
```

### Auto-Detection of Config Flags

The provider-openai module already handles auto-detection:

1. **If `base_url` is set**: All feature flags default to `false`
2. **If `base_url` is NOT set**: All feature flags default to `true` (standard OpenAI)
3. **Explicit flags override auto-detection**: Users can override any flag

For OpenRouter, we explicitly set the flags that work (`true`) and those that don't (`false`) in the provider YAML, ensuring correct behavior without requiring users to understand the internal flags.

### Model Listing via OpenRouter API

OpenRouter provides a public API to list available models:

```bash
# Public endpoint (no auth required)
curl https://openrouter.ai/api/v1/models | jq '.data[] | {id, name}'
```

#### Implementation

Add a `--list-models` flag to `amplifier provider use openrouter`:

```bash
$ amplifier provider use openrouter --list-models

Available models on OpenRouter:
  anthropic/claude-3.5-sonnet      (Anthropic)
  anthropic/claude-3-opus          (Anthropic)
  deepseek/deepseek-chat-v3-0324   (DeepSeek)
  google/gemini-2.0-flash-exp      (Google)
  openai/gpt-4.1                   (OpenAI)
  ...
```

#### Filter Options

```bash
# Filter by provider
amplifier provider use openrouter --list-models --provider anthropic

# Filter by capability
amplifier provider use openrouter --list-models --has-tools
```

---

## Files to Create/Modify

### New Files

1. `amplifier-foundation/providers/openrouter.yaml` - Provider configuration
2. `amplifier-foundation/utils/providers.py` - Add "openrouter" to PROVIDERS dict

### Existing Files to Modify

1. Amplifier CLI - Add "openrouter" to provider use command
2. Documentation - Add OpenRouter to provider documentation

---

## Future Enhancements

### Priority 2

- **Site-specific routing**: Allow users to specify alternative OpenRouter-compatible endpoints (e.g., generic proxies)
- **Referral code support**: Add config for OpenRouter referral codes
- **Cost tracking**: Integrate OpenRouter's cost estimation API

### Priority 3

- **Model favorites**: Remember user's frequently used models
- **Auto-model-suggest**: Suggest models based on task type (reasoning, coding, etc.)

---

## Summary

| Aspect | Design Decision |
|--------|-----------------|
| **Provider YAML** | `providers/openrouter.yaml` with base_url + explicit feature flags |
| **CLI command** | `amplifier provider use openrouter --model <model-id>` |
| **Auto-detection** | Pre-configured via YAML; user doesn't need to know flags |
| **Model listing** | `--list-models` fetches from OpenRouter's `/models` endpoint |
| **Feature flags** | enable_native_tools=true, enable_reasoning_replay=true, enable_store=false, enable_background=false |

---

## Related

- [provider-openai module](https://github.com/microsoft/amplifier-module-provider-openai)
- [OpenRouter API docs](https://openrouter.ai/docs/api-reference)
- [PR #17: Custom endpoint config flags](https://github.com/microsoft/amplifier-module-provider-openai/pull/17)