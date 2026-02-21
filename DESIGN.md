# Design: Setup Improvements for amplifier-bundle-workgraph

**Date**: 2026-02-21
**Status**: Proposal (iteration 1 — post-audit)
**Scope**: What we control now — no upstream changes to workgraph or amplifier-core

---

## Current State Audit

The iteration 0 design specified 7 changes. All 7 are now present in the codebase (commit `44db0fc`, v0.2.0). However, **several have bugs or incomplete implementations**. This iteration focuses on fixing those issues.

### What's working

| Feature | Status | Evidence |
|---------|--------|----------|
| Version stamps on executor files | **OK** | `amplifier.toml` line 1, `amplifier-run.sh` line 3 |
| `wg-executor-protocol.md` in behavior context | **OK** | `behaviors/workgraph.yaml` includes both context files |
| `hook-shell` module in bundle | **OK** | `bundle.md` frontmatter has `hooks: [{module: hook-shell}]` |
| Provider sync script | **OK** | `scripts/sync-provider-cache.sh` reads settings, diffs, copies |
| ARG_MAX guard in wrapper | **OK** | `amplifier-run.sh` lines 63-66 |
| README restructured | **OK** | Quick Start → Troubleshooting → Manual Install (appendix) |
| Setup.sh 5-step flow | **PARTIAL** | Steps 1-5 execute, but `--check` mode broken (see below) |

### What's broken or missing

| Issue | Severity | Details |
|-------|----------|---------|
| `setup.sh --check` non-functional | **Critical** | Flag is parsed (line 42) but `$CHECK_MODE` is never referenced. All 5 steps always execute — `--check` modifies the system. |
| `check-setup.sh` uses `grep -oP` | **High** | Perl regex flag is GNU-only. Fails silently on macOS. |
| PyYAML dependency not guaranteed | **High** | Both `check-setup.sh` and `setup.sh` call `python3 -c "import yaml"`. PyYAML is not in the Python stdlib. Fails on fresh systems. |
| JSON output fragile in hook | **Medium** | `printf '{"contextInjection": "%s"}'` breaks if any issue message contains `"`, `%`, or actual newlines. |
| SessionStart hook matcher | **Medium** | `"matcher": "startup"` — SessionStart is a lifecycle event, not a tool use. The hook-shell module matches against tool names via regex. For lifecycle events, the matcher should likely be `"*"` or `".*"`. Needs verification. |
| No tests for new features | **Medium** | Integration tests cover original 6 groups (21 assertions). Nothing tests `--check` mode, version stamp parsing, hook install, or provider sync. |
| Version in 4 places | **Low** | `setup.sh`, `check-setup.sh`, `amplifier.toml` comment, `amplifier-run.sh` comment. Manual sync on bump. |
| `executor/install.sh` redundant | **Low** | `setup.sh` does everything `install.sh` does and more. `install.sh` is still referenced in tests. |

---

## Changes

### Change 1: Implement `--check` mode in setup.sh

**Goal**: `./setup.sh --check` validates the setup without modifying anything.

**File**: `setup.sh`

**What to do**: Add conditional branching on `$CHECK_MODE` so that when `--check` is set, each step only reports status. The structure should be:

```bash
# After argument parsing, if CHECK_MODE:
if [ "$CHECK_MODE" = true ]; then
    echo "=== Amplifier + Workgraph Setup Check (v$BUNDLE_VERSION) ==="
    echo ""
    ISSUES=0

    # 1. Prerequisites
    echo "[1/5] Prerequisites..."
    command -v amplifier &>/dev/null && echo "      amplifier: $(command -v amplifier) ✓" \
        || { echo "      amplifier: NOT FOUND ✗"; ISSUES=$((ISSUES+1)); }
    command -v wg &>/dev/null && echo "      wg: $(command -v wg) ✓" \
        || { echo "      wg: NOT FOUND ✗"; ISSUES=$((ISSUES+1)); }

    # 2. Bundle
    echo "[2/5] Bundle..."
    if amplifier bundle list 2>/dev/null | grep -q "workgraph"; then
        echo "      Bundle 'workgraph' installed ✓"
    else
        echo "      Bundle 'workgraph' NOT installed ✗"
        ISSUES=$((ISSUES+1))
    fi

    # 3. Executor
    echo "[3/5] Executor..."
    if [ -f ".workgraph/executors/amplifier.toml" ]; then
        # Version check (portable — no grep -oP)
        INSTALLED_VER=$(sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p' .workgraph/executors/amplifier.toml)
        INSTALLED_VER="${INSTALLED_VER:-unknown}"
        if [ "$INSTALLED_VER" = "$BUNDLE_VERSION" ]; then
            echo "      amplifier.toml v$INSTALLED_VER ✓"
        else
            echo "      amplifier.toml v$INSTALLED_VER (expected v$BUNDLE_VERSION) ✗"
            ISSUES=$((ISSUES+1))
        fi
    else
        echo "      amplifier.toml NOT FOUND ✗"
        ISSUES=$((ISSUES+1))
    fi
    if [ -x ".workgraph/executors/amplifier-run.sh" ]; then
        echo "      amplifier-run.sh ✓ (executable)"
    else
        echo "      amplifier-run.sh MISSING or not executable ✗"
        ISSUES=$((ISSUES+1))
    fi

    # 4. Default executor
    echo "[4/5] Default executor..."
    if [ -f ".workgraph/config.toml" ] && grep -q 'executor.*=.*"amplifier"' .workgraph/config.toml 2>/dev/null; then
        echo "      Coordinator executor = amplifier ✓"
    else
        echo "      Coordinator executor NOT set to amplifier ✗"
        ISSUES=$((ISSUES+1))
    fi

    # 5. Hook
    echo "[5/5] Validation hook..."
    if [ -f ".amplifier/hooks/workgraph-setup/hooks.json" ] && [ -x ".amplifier/hooks/workgraph-setup/check-setup.sh" ]; then
        echo "      .amplifier/hooks/workgraph-setup/ ✓"
    else
        echo "      Validation hook NOT installed ✗"
        ISSUES=$((ISSUES+1))
    fi

    # Provider check (informational)
    # ... same as current provider check block ...

    echo ""
    if [ "$ISSUES" -eq 0 ]; then
        echo "=== All checks passed ==="
        exit 0
    else
        echo "=== $ISSUES issue(s) found ==="
        echo "Run ./setup.sh (without --check) to fix."
        exit 1
    fi
fi

# ... rest of the script (install mode) unchanged ...
```

**Exit codes**: 0 = healthy, 1 = issues found, 2 = missing prerequisites (install mode only).

---

### Change 2: Fix portability issues in check-setup.sh

**Goal**: Make the hook script work on macOS and systems without PyYAML.

**File**: `hooks/workgraph-setup/check-setup.sh`

**Changes**:

1. **Replace `grep -oP` with `sed`** (POSIX-compliant):
   ```bash
   # Before (GNU-only):
   INSTALLED_VER=$(head -1 .workgraph/executors/amplifier.toml | grep -oP 'v\K[0-9.]+' || echo "unknown")

   # After (POSIX):
   INSTALLED_VER=$(sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p' .workgraph/executors/amplifier.toml)
   INSTALLED_VER="${INSTALLED_VER:-unknown}"
   ```

2. **Replace PyYAML with grep for settings.yaml parsing**:
   ```bash
   # Before (requires PyYAML):
   OVERRIDE=$(python3 -c "import yaml; ..." 2>/dev/null || true)

   # After (grep — settings.yaml is simple enough):
   OVERRIDE=""
   if [ -f "$SETTINGS" ]; then
       # Look for "provider-openai: /path/to/dir" under sources.modules
       OVERRIDE=$(grep -A1 'provider-openai' "$SETTINGS" 2>/dev/null \
           | tail -1 | sed 's/^[[:space:]]*provider-openai:[[:space:]]*//' | tr -d "'\"")
       # Validate it looks like a path
       if [ -n "$OVERRIDE" ] && [ ! -d "$OVERRIDE" ]; then
           OVERRIDE=""
       fi
   fi
   ```

   Note: This works because `settings.yaml` has a flat structure for source overrides. A line like `provider-openai: /home/erik/amplifier/.amplifier/modules/provider-openai` is parseable with grep+sed. For deeply nested YAML, we'd need PyYAML, but we don't.

3. **Fix JSON escaping in output**:
   ```bash
   # Before (fragile):
   MSG="WORKGRAPH SETUP ISSUES:\\n"
   for issue in "${ISSUES[@]}"; do
       MSG+="  - $issue\\n"
   done
   printf '{"contextInjection": "%s"}' "$MSG"

   # After (proper escaping):
   MSG="WORKGRAPH SETUP ISSUES:"
   for issue in "${ISSUES[@]}"; do
       MSG+=$'\n'"  - $issue"
   done
   # Escape for JSON: replace \ with \\, " with \", newlines with \n
   ESCAPED=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
   printf '{"contextInjection": "%s"}\n' "$ESCAPED"
   ```

   Alternatively, if `jq` is available, use it:
   ```bash
   if command -v jq &>/dev/null; then
       printf '%s' "$MSG" | jq -Rs '{contextInjection: .}'
   else
       # manual escaping fallback
   fi
   ```

---

### Change 3: Fix SessionStart hook matcher

**Goal**: Ensure the hook actually fires on session start.

**File**: `hooks/workgraph-setup/hooks.json`

**Analysis**: The hook-shell module matches hooks via regex against the "tool name". For lifecycle events like `SessionStart`, the event name itself is used as the match target. The current matcher `"startup"` won't match `"SessionStart"`. It should be `".*"` (match anything) since there's only one SessionStart event per session.

**Change**:
```json
{
  "description": "Verify workgraph+amplifier setup health on session start",
  "hooks": {
    "SessionStart": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "${AMPLIFIER_HOOKS_DIR}/workgraph-setup/check-setup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Verification**: After changing this, start an Amplifier session in a project with a known issue (e.g., remove the executor TOML temporarily) and confirm the warning appears in context.

---

### Change 4: Apply same portability fix to setup.sh provider check

**Goal**: setup.sh should not depend on PyYAML either.

**File**: `setup.sh` (lines 214-236)

**Change**: Replace the `python3 -c "import yaml"` block with the same grep-based approach from Change 2:

```bash
# Provider patch check (informational only)
SETTINGS="$HOME/.amplifier/settings.yaml"
if [ -f "$SETTINGS" ]; then
    OVERRIDE=$(grep 'provider-openai' "$SETTINGS" 2>/dev/null \
        | sed 's/^[[:space:]]*provider-openai:[[:space:]]*//' | tr -d "'\"" | head -1)

    if [ -n "$OVERRIDE" ] && [ -d "$OVERRIDE" ]; then
        CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
        # ... rest unchanged ...
    fi
fi
```

---

### Change 5: Add integration tests for new features

**Goal**: Test the features added in v0.2.0.

**File**: `tests/test_integration.sh`

**New test groups to add** (after existing Test 5, before Test 6):

```bash
# --------------------------------------------------------------------------
# Test 6: Version stamp parsing
# --------------------------------------------------------------------------
echo ""
echo "Test 6: Version stamps"

# amplifier.toml version stamp
VER=$(sed -n '1s/.*v\([0-9][0-9.]*\).*/\1/p' "$BUNDLE_DIR/executor/amplifier.toml")
if [ -n "$VER" ]; then
    pass "amplifier.toml has version stamp: v$VER"
else
    fail "amplifier.toml has version stamp" "No version found on line 1"
fi

# amplifier-run.sh version stamp
VER=$(sed -n '1,3s/.*amplifier-bundle-workgraph v\([0-9][0-9.]*\).*/\1/p' "$BUNDLE_DIR/executor/amplifier-run.sh")
if [ -n "$VER" ]; then
    pass "amplifier-run.sh has version stamp: v$VER"
else
    fail "amplifier-run.sh has version stamp" "No version found in first 3 lines"
fi

# --------------------------------------------------------------------------
# Test 7: Hook structure
# --------------------------------------------------------------------------
echo ""
echo "Test 7: SessionStart hook"

HOOK_DIR="$BUNDLE_DIR/hooks/workgraph-setup"

if [ -f "$HOOK_DIR/hooks.json" ]; then
    pass "hooks.json exists"
else
    fail "hooks.json exists" "Not found: $HOOK_DIR/hooks.json"
fi

# Validate hooks.json is valid JSON
if python3 -c "import json; json.load(open('$HOOK_DIR/hooks.json'))" 2>/dev/null; then
    pass "hooks.json is valid JSON"
else
    fail "hooks.json is valid JSON" "JSON parse error"
fi

# Check hook references SessionStart
if grep -q "SessionStart" "$HOOK_DIR/hooks.json"; then
    pass "hooks.json references SessionStart event"
else
    fail "hooks.json references SessionStart event" "SessionStart not found"
fi

if [ -f "$HOOK_DIR/check-setup.sh" ]; then
    pass "check-setup.sh exists"
else
    fail "check-setup.sh exists" "Not found"
fi

if [ -x "$HOOK_DIR/check-setup.sh" ]; then
    pass "check-setup.sh is executable"
else
    fail "check-setup.sh is executable" "Not executable"
fi

# --------------------------------------------------------------------------
# Test 8: Provider sync script
# --------------------------------------------------------------------------
echo ""
echo "Test 8: Provider sync script"

SYNC_SCRIPT="$BUNDLE_DIR/scripts/sync-provider-cache.sh"

if [ -f "$SYNC_SCRIPT" ]; then
    pass "sync-provider-cache.sh exists"
else
    fail "sync-provider-cache.sh exists" "Not found"
fi

if [ -x "$SYNC_SCRIPT" ]; then
    pass "sync-provider-cache.sh is executable"
else
    fail "sync-provider-cache.sh is executable" "Not executable"
fi

# Test with no settings file — should exit 0 gracefully
HOME_BAK="$HOME"
export HOME=$(mktemp -d)
OUTPUT=$("$SYNC_SCRIPT" 2>&1) && pass "Gracefully handles missing settings.yaml" \
    || fail "Gracefully handles missing settings.yaml" "Exit non-zero: $OUTPUT"
export HOME="$HOME_BAK"

# --------------------------------------------------------------------------
# Test 9: setup.sh --check mode (once implemented)
# --------------------------------------------------------------------------
echo ""
echo "Test 9: setup.sh --check mode"

# In a temp dir with no .workgraph, --check should find issues and exit 1
CHECK_DIR=$(mktemp -d)
if (cd "$CHECK_DIR" && "$BUNDLE_DIR/setup.sh" --check 2>/dev/null); then
    fail "setup.sh --check detects missing .workgraph" "Expected exit 1, got 0"
else
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 1 ]; then
        pass "setup.sh --check detects issues (exit 1)"
    elif [ "$EXIT_CODE" -eq 2 ]; then
        skip "setup.sh --check (missing prerequisites)"
    else
        fail "setup.sh --check detects issues" "Expected exit 1, got $EXIT_CODE"
    fi
fi
rm -rf "$CHECK_DIR"

# In a properly set up dir, --check should pass
GOOD_DIR=$(mktemp -d)
(cd "$GOOD_DIR" && "$BUNDLE_DIR/setup.sh" 2>/dev/null)  # First, set up properly
if (cd "$GOOD_DIR" && "$BUNDLE_DIR/setup.sh" --check 2>/dev/null); then
    pass "setup.sh --check passes for healthy setup (exit 0)"
else
    fail "setup.sh --check passes for healthy setup" "Expected exit 0"
fi
rm -rf "$GOOD_DIR"
```

**Renumber**: Move the existing e2e lifecycle test to Test 10.

---

### Change 6: Deprecate executor/install.sh

**Goal**: Avoid confusing users with two ways to install the executor.

**File**: `executor/install.sh`

**Change**: Add a deprecation notice to the top that points to `setup.sh`:

```bash
#!/usr/bin/env bash
# DEPRECATED: Use setup.sh instead (does everything this script does plus more).
#
# This script is kept for backwards compatibility.
echo "NOTE: install.sh is deprecated. Use setup.sh instead for full setup."
echo ""
```

Leave the rest of the script functional so existing automation doesn't break.

**File**: `README.md` — no changes needed (already leads with `setup.sh`).

---

## Implementation Order

| Phase | Step | Files | Risk | Dependencies |
|-------|------|-------|------|-------------|
| **1. Portability** | 1a. Fix `grep -oP` in check-setup.sh | `hooks/workgraph-setup/check-setup.sh` | Low | None |
| | 1b. Replace PyYAML with grep in check-setup.sh | `hooks/workgraph-setup/check-setup.sh` | Low | None |
| | 1c. Fix JSON escaping in check-setup.sh | `hooks/workgraph-setup/check-setup.sh` | Low | None |
| | 1d. Replace PyYAML with grep in setup.sh | `setup.sh` | Low | None |
| **2. Functionality** | 2a. Implement --check mode in setup.sh | `setup.sh` | Medium | 1d |
| | 2b. Fix SessionStart hook matcher | `hooks/workgraph-setup/hooks.json` | Low | None |
| **3. Cleanup** | 3a. Add deprecation notice to install.sh | `executor/install.sh` | Low | None |
| **4. Tests** | 4a. Add tests for version stamps, hook, sync, --check | `tests/test_integration.sh` | Low | 1a-2b |

**Estimated scope**: ~200 lines of changes across 5 files. No new files needed.

**Testing at each phase**:
- Phase 1: Run `bash hooks/workgraph-setup/check-setup.sh` manually in a project dir — verify no errors
- Phase 2: Run `./setup.sh --check` in a healthy dir (exit 0) and broken dir (exit 1)
- Phase 3: Run `./executor/install.sh /tmp/test` — verify deprecation message prints
- Phase 4: `./tests/test_integration.sh --quick` — all tests pass

---

## Files Summary

### Modified files

| File | Changes |
|------|---------|
| `hooks/workgraph-setup/check-setup.sh` | Replace `grep -oP` with `sed`, replace PyYAML with grep, fix JSON escaping |
| `hooks/workgraph-setup/hooks.json` | Change matcher from `"startup"` to `".*"` |
| `setup.sh` | Implement `--check` mode (new code path), replace PyYAML with grep |
| `executor/install.sh` | Add deprecation notice |
| `tests/test_integration.sh` | Add 4 new test groups (version stamps, hook, provider sync, --check) |

### Unchanged files (and why)

| File | Reason |
|------|--------|
| `executor/amplifier.toml` | Version stamp already correct |
| `executor/amplifier-run.sh` | Version stamp and ARG_MAX guard already correct |
| `behaviors/workgraph.yaml` | Already includes both context files |
| `bundle.md` | Already includes hook-shell |
| `README.md` | Already restructured with troubleshooting |
| `scripts/sync-provider-cache.sh` | Working correctly (uses PyYAML but that's OK for a manually-run script — user can install it) |
| `CONTEXT-TRANSFER.md` | Update AFTER implementation, not during design |

---

## What We're NOT Doing (and Why)

1. **Not centralizing the version number** — Tempting to extract `BUNDLE_VERSION` to a single file and source it everywhere, but the version appears in shell comments (`.toml` line 1, `.sh` line 3) that can't source a file. A `Makefile` or `bump-version.sh` script would add tooling complexity for a 4-place grep-replace on release. Not worth it at this scale.

2. **Not removing PyYAML from sync-provider-cache.sh** — This script is run manually by users who already have a patched Python provider module. They certainly have PyYAML. The hook and setup.sh need the fix because they run automatically on every session.

3. **Not rewriting the hook in Python** — Would solve the JSON escaping and YAML parsing issues cleanly, but adds a Python dependency to what should be a lightweight shell hook. Shell is the right choice for a 10-second timeout hook.

4. **Not adding `--stdin` to amplifier CLI** — Still needs an upstream feature request. Document the ARG_MAX limitation and move on.

---

## Success Criteria

After implementing this design:

| Scenario | Expected |
|----------|----------|
| `./setup.sh --check` in healthy dir | Exit 0, all checks pass |
| `./setup.sh --check` in empty dir | Exit 1, lists missing components |
| `./setup.sh --check` with stale executor | Exit 1, reports version mismatch |
| Start Amplifier session with missing executor | SessionStart hook injects warning |
| `./tests/test_integration.sh --quick` | All tests pass (old + new) |
| Run on macOS | No `grep -oP` failures, no PyYAML dependency |
