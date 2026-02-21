# Review: Setup Improvements

**Reviewer**: review-setup-improvements
**Date**: 2026-02-21
**Iteration**: 1 (second review)

## Summary

The implementation is **substantially complete**. All 7 DESIGN.md changes are present in the codebase and working, with one functional bug: the `--check` mode in setup.sh is parsed but not implemented (the flag is accepted but the script runs the full install regardless). Integration tests pass 21/21. Executor spawns correctly and completes tasks end-to-end.

## Test Results

### 1. Clean setup.sh run (/tmp/wg-review-test/) — PASS

- [1/5] Prerequisites detected (amplifier + wg) — **PASS**
- [2/5] Bundle added to Amplifier — **PASS**
- [3/5] Executor installed (.workgraph/executors/) — **PASS**
- [4/5] Default executor set — **PASS**
- [5/5] Validation hook installed (.amplifier/hooks/) — **PASS**
- Version stamps present in installed files — **PASS**

### 2. Executor spawn — PASS

- Created task, spawned with `wg spawn --executor amplifier`
- Agent completed in ~55s, created expected file, marked done
- Full lifecycle works: spawn → work → artifact → done

### 3. Integration tests — PASS

- 21/21 quick tests pass, 0 failed, 1 skipped (e2e)
- Executor TOML validity, install script, flag forwarding, bundle structure all pass

### 4. SessionStart hook validation — PASS

- Hook returns exit 0 (no output) when setup is healthy
- Hook returns contextInjection JSON when executor TOML is missing
- Provider patch check logic is present and correct

### 5. --check mode — **FAIL**

- `CHECK_MODE` variable is parsed on line 41 but **never referenced** in the script body
- Running `./setup.sh --check` performs the full install (adds bundle, copies executor, installs hooks)
- Expected behavior: read-only validation, exit 0 if healthy, exit 1 if not

## DESIGN.md Changes — Status

| # | Change | Status | Notes |
|---|--------|--------|-------|
| 1 | Version-stamped executor files | **DONE** | `amplifier.toml` line 1, `amplifier-run.sh` line 3 |
| 2 | SessionStart hook | **DONE** | `hooks/workgraph-setup/` with hooks.json + check-setup.sh |
| 3 | Smarter setup.sh | **PARTIAL** | --force, PROJECT_DIR, version detection all work. **--check mode not implemented** (flag parsed but ignored) |
| 4 | Provider sync script | **DONE** | `scripts/sync-provider-cache.sh` — reads settings, finds cache, syncs |
| 5 | ARG_MAX guard | **DONE** | 128KB warning in amplifier-run.sh lines 63-66 |
| 6 | Executor protocol in behavior | **DONE** | `behaviors/workgraph.yaml` includes both context files |
| 7 | README restructure | **DONE** | Leads with setup.sh, troubleshooting section, manual install as appendix |
| — | hook-shell in bundle.md | **DONE** | `hooks:` section added to bundle.md frontmatter |
| — | CONTEXT-TRANSFER.md updated | **DONE** | Documents all changes, remaining work, file layout |

## What Needs Fixing (for next iteration)

### Bug: `--check` mode not implemented in setup.sh

**Location**: `setup.sh` lines 35-62 (parsing) and everywhere after (missing guards)

**Problem**: The `CHECK_MODE=true` flag is set when `--check` is passed, but no code path checks this variable. The script runs the full install regardless.

**Fix**: After parsing arguments, if `CHECK_MODE=true`, run the same validation checks as `check-setup.sh` (or invoke it directly) and exit with appropriate code. Specifically:

1. Check prerequisites (wg, amplifier on PATH)
2. Check if bundle is installed (`amplifier bundle list | grep workgraph`)
3. Check executor files exist and version matches
4. Check coordinator executor is set
5. Check hook is installed
6. Report results and exit 0 (healthy) or 1 (issues found)

Do NOT run `amplifier bundle add`, `cp`, `wg config`, or any other mutating commands in check mode.

### Minor: No tests for new components

The DESIGN.md specifies adding tests for hooks, setup --check, version stamps, and provider sync to `tests/test_integration.sh`. These were not added. The existing 21 tests pass, but the new features are untested in the automated suite.

## Verdict

**NOT CONVERGED** — One functional bug remains: `--check` mode is advertised in help text, README, and CONTEXT-TRANSFER.md but does not work. Fix the `--check` implementation in setup.sh, then this is ready to ship.
