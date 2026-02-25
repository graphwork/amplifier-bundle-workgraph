# OpenRouter Provider Review

**Review Date**: 2026-02-24  
**Reviewer**: or-verify  
**Status**: Issues Found (Requires Iteration)

---

## Summary

The OpenRouter provider implementation is **partially working** with some documentation and UX issues that need to be addressed. The core functionality works - OpenRouter can be configured and used - but the setup experience has gaps that could confuse users.

---

## Test Results

### Test 1: Does documented config work with Amplifier?

**Result**: WORKS (with caveat)

**Details**:
- The configuration in `~/.amplifier/settings.yaml` is correctly parsed and applied
- When configured with `base_url: https://openrouter.ai/api/v1`, the provider automatically disables OpenAI-specific features that OpenRouter doesn't support:
  - `enable_native_tools = false`
  - `enable_reasoning_replay = false`
  - `enable_store = false`
  - `enable_background = false`

**Issue Found**: 
- The provider is mounted internally as "openai", not "openrouter"
- Running `amplifier run --provider openrouter` fails with "Provider 'openrouter' not configured"
- Users must run `amplifier run --provider openai` to use their OpenRouter configuration

**Recommendation**: The setup guide should document that users must use `--provider openai` to access their OpenRouter configuration.

---

### Test 2: Can user follow setup guide to configure OpenRouter?

**Result**: PARTIALLY

**Details**:
- The setup guide provides correct YAML configuration
- The guide accurately describes getting an API key from openrouter.ai/keys
- The manual config steps (lines 51-61) are accurate

**Gaps**:
1. No mention that `--provider openai` must be used (not `--provider openrouter`)
2. No mention of available config flags (see Test 3)
3. No troubleshooting for "Provider 'openrouter' not configured" error

---

### Test 3: Are config flags documented?

**Result**: NOT DOCUMENTED

**Details**:
The following config flags exist in the provider but are NOT documented in the setup guide:

| Flag | Default for OpenRouter | Purpose |
|------|----------------------|---------|
| `enable_native_tools` | `false` | Enable OpenAI apply_patch_call tool format |
| `enable_reasoning_replay` | `false` | Enable encrypted reasoning state preservation |
| `enable_store` | `false` | Enable OpenAI Store (memory) feature |
| `enable_background` | `false` | Enable background/async mode |

**Why This Matters**:
- Advanced users may want to enable some of these features if their specific OpenRouter model supports them
- The current behavior (auto-disable) is correct, but users should know these exist
- The flags can be explicitly enabled in config if needed

**Example use case**: A user using a specific OpenRouter model that supports native tools might want to set `enable_native_tools: true` in their config.

---

### Test 4: Does amplifier run with -B workgraph still work?

**Result**: WORKS

**Details**:
```bash
$ amplifier run -B workgraph "What is the current directory?"
Bundle: workgraph | Provider: OpenAI | minimax/minimax-m2.5
The current working directory is /home/erik/amplifier.
```

The workgraph bundle loads correctly and uses the default provider (which is configured to use OpenRouter with minimax model).

---

## Issues Summary

| # | Issue | Severity | Type |
|---|-------|----------|------|
| 1 | Provider name mismatch (openai vs openrouter) | Medium | UX/Documentation |
| 2 | Config flags not documented | Low | Documentation |
| 3 | No troubleshooting for provider errors | Low | Documentation |

---

## Recommendations

### 1. Update SETUP_GUIDE.md

Add a note after the configuration example:

**Important**: The provider is mounted internally as "openai", not "openrouter".
Use `--provider openai` when running Amplifier:

```bash
amplifier run "Your prompt" --provider openai
```

### 2. Add Config Flags Documentation

Add a section to the setup guide:

### Advanced: OpenRouter-Specific Options

When using OpenRouter, the following features are automatically disabled (since 
OpenRouter doesn't support all OpenAI Responses API features). You can override:

| Option | Default | Description |
|--------|---------|-------------|
| `enable_native_tools` | false | Enable OpenAI apply_patch_call tool format |
| `enable_reasoning_replay` | false | Enable reasoning state preservation |
| `enable_store` | false | Enable OpenAI Store feature |
| `enable_background` | false | Enable background/async mode |

Example to enable native tools if your model supports it:

```yaml
config:
  providers:
    - name: openrouter
      module: provider-openai
      config:
        api_key: sk-or-v1-...
        base_url: https://openrouter.ai/api/v1
        default_model: anthropic/claude-3.5-sonnet
        enable_native_tools: true
```

### 3. Add Troubleshooting Section

Add to troubleshooting:

### "Provider 'openrouter' not configured"

You're using `--provider openrouter` but the provider is mounted as "openai".
Use `--provider openai` instead:

```bash
amplifier run "Your prompt" --provider openai
```

---

## Verification Evidence

```
# Test 1: Config loaded
$ cat ~/.amplifier/settings.yaml | grep -A10 providers:
  - config:
      api_key: sk-or-v1-...
      base_url: https://openrouter.ai/api/v1
      default_model: minimax/minimax-m2.5
    module: provider-openai
    name: openrouter
    source: git+https://github.com/microsoft/amplifier-module-provider-openai@main

# Test 1: Running with correct provider
$ amplifier run "Say 'test successful'" --provider openai
Bundle: foundation | Provider: OpenAI | minimax/minimax-m2.5
test successful

# Test 4: Workgraph bundle
$ amplifier run -B workgraph "What is the current directory?"
Bundle: workgraph | Provider: OpenAI | minimax/minimax-m2.5
The current working directory is /home/erik/amplifier.
```

---

## Conclusion

The OpenRouter implementation is **functional** but needs documentation improvements. All tests pass when using the correct `--provider openai` flag. The main gap is the provider name mismatch which causes confusion.

**Recommendation**: Mark this task as requiring iteration to fix the documentation issues before marking converged.
