# Multi-Provider Configuration: Implementation & Test Review

**Date**: 2026-02-25
**Task**: implement-and-test
**Status**: Tests partially pass (see details below)

---

## Summary

Amplifier's multi-provider configuration **works** for providers using different modules
(e.g., Anthropic + OpenRouter). Both can coexist in `settings.yaml`, and `--provider`
correctly selects between them. However, there are gaps around same-module multi-provider
scenarios and the current user's config has a missing API key that prevents the Anthropic
provider from loading.

---

## Test Results

### Test 1: Can a user have both OpenRouter and direct Anthropic configured?

**Result: PASS (structurally) / PARTIAL (functionally)**

The user's `~/.amplifier/settings.yaml` already contains both:
- `provider-anthropic` (priority 1) — direct Anthropic API
- `provider-openai` with `name: openrouter` (priority 10) — OpenRouter

Both entries are parsed correctly. `amplifier provider current` reports:
```
Active provider: anthropic
  Source: global
  Model: claude-sonnet-4-20250514
```

**However**, the Anthropic provider fails to mount because:
- No `api_key` field in the provider config
- No `ANTHROPIC_API_KEY` environment variable set

This causes the warning:
```
No API key found for Anthropic provider
Partial provider failure: 1/2 loaded. Failed: {'anthropic'}. Loaded: ['openai'].
Session continuing with available providers.
```

The OpenRouter provider loads successfully and serves as fallback.

**Fix needed**: Add `api_key` to the Anthropic provider config in `settings.yaml`, or
export `ANTHROPIC_API_KEY` in the environment.

---

### Test 2: Does `amplifier run --provider <name>` correctly select the right provider?

**Result: PASS**

| Command | Expected | Actual | Status |
|---------|----------|--------|--------|
| `amplifier run --provider openai "..."` | OpenRouter (minimax) | `model: openai/minimax/minimax-m2.5` | PASS |
| `amplifier run --provider openai --model anthropic/claude-sonnet-4 "..."` | OpenRouter (Claude via OR) | `model: openai/anthropic/claude-sonnet-4` | PASS |
| `amplifier run --provider anthropic "..."` | Anthropic direct | Falls back to openai (no API key) | EXPECTED FAIL |
| `amplifier run --provider openrouter "..."` | OpenRouter | `Error: Provider 'openrouter' not configured` | EXPECTED FAIL |

**Key findings**:

1. **`--provider` uses module shorthand, not the `name:` field.** The provider named
   "openrouter" in settings.yaml must be accessed via `--provider openai` because it uses
   the `provider-openai` module. `--provider openrouter` fails with "not configured".

2. **Priority-based fallback works.** When the Anthropic provider fails (no API key),
   sessions continue with the next available provider (openai/OpenRouter).

3. **Model override works.** `--provider openai --model anthropic/claude-sonnet-4`
   correctly routes through OpenRouter to the specified model.

4. **Provider selection sets priority 0.** When `--provider openai` is specified, that
   provider gets priority 0 for the session, overriding the default priority ordering.

---

### Test 3: SETUP_GUIDE.md Updated

**Result: PASS**

Added a new **Step 2b: Multi-Provider Configuration** section to
`docs/SETUP_GUIDE.md` covering:
- How multi-provider works (priority system)
- Example config with Anthropic + OpenRouter
- Switching providers with `--provider` and `amplifier provider use`
- Provider name vs module ID mapping table
- Limitation: same-module providers can't be distinguished via `--provider`
- Troubleshooting: "No API key found" error

---

## Architecture Notes

### Provider Loading Flow

1. **Settings merge**: global → project → local (lists are replaced, not merged)
2. **All providers loaded**: Amplifier attempts to mount every provider in the list
3. **Partial failure tolerated**: If some providers fail, others still work
4. **Priority selection**: Orchestrator picks the lowest-priority-number provider
5. **`--provider` override**: Sets the selected provider to priority 0 for the session

### Provider Registration (Hardcoded Names)

Each module hardcodes its mount name:
- `provider-anthropic` → `coordinator.mount("providers", provider, name="anthropic")`
- `provider-openai` → `coordinator.mount("providers", provider, name="openai")`

This means the `name:` field in settings.yaml is purely cosmetic. The `--provider` flag
matches against the module shorthand (e.g., "openai" → "provider-openai").

### Same-Module Limitation

If a user wants both direct OpenAI and OpenRouter, both use `provider-openai`. Since the
module hardcodes `name="openai"`, the second mount would overwrite the first. There's
currently no way to have two instances of the same module with different names.

**Workaround**: Use `amplifier provider use` to switch the default, or manually edit
priorities in settings.yaml between sessions.

---

## Issues Found

| # | Severity | Description | Impact |
|---|----------|-------------|--------|
| 1 | **High** | Anthropic provider has no `api_key` in user's settings.yaml | Provider fails to load; only OpenRouter works |
| 2 | **Medium** | `--provider` uses module shorthand, not `name:` field | Users who set `name: openrouter` will try `--provider openrouter` and get an error |
| 3 | **Medium** | Same-module providers can't coexist | Can't have OpenAI direct + OpenRouter simultaneously |
| 4 | **Low** | `provider current` shows "anthropic" even when it can't load | Misleading — reports based on config priority, not runtime health |

---

## Recommendations

1. **Immediate**: Add `api_key` to the Anthropic provider config, or set
   `ANTHROPIC_API_KEY` in the user's shell profile.

2. **Short-term**: Update `amplifier provider current` to report runtime health
   (whether the provider actually loads), not just config priority.

3. **Medium-term**: Support `--provider <name>` matching the `name:` field in
   settings.yaml, falling back to module shorthand. This would let users name
   their providers (e.g., `openrouter`) and use that name with `--provider`.

4. **Long-term**: Allow multiple instances of the same module with different names
   (e.g., `openai-direct` and `openai-openrouter`), each with independent config.

---

## Conclusion

Multi-provider configuration **works** for the primary use case: having providers
from different modules (Anthropic + OpenRouter) and switching between them. The
priority system and `--provider` flag function as designed.

The main gaps are:
- UX friction around provider naming (`--provider openai` for OpenRouter)
- No support for multiple instances of the same module
- The user's specific config needs an Anthropic API key to be fully functional

**Verdict**: Tests pass with caveats. The multi-provider system is functional but
has UX gaps that should be addressed in a follow-up design iteration.
