#!/usr/bin/env bash
# Workgraph+Amplifier setup validation hook.
# Runs on every Amplifier session start to detect setup issues.
#
# This script checks:
# 1. wg is on PATH
# 2. If .workgraph/ exists:
#    - Executor TOML exists and version matches
#    - Wrapper script exists and is executable
#    - Coordinator executor is set to amplifier
# 3. Provider patch staleness (if source override exists)

set -euo pipefail

ISSUES=()
BUNDLE_VERSION="0.2.0"  # Keep in sync with bundle.md

# 1. Check wg on PATH
if ! command -v wg &>/dev/null; then
    ISSUES+=("wg CLI not found on PATH")
fi

# 2. Check .workgraph/ — only run executor checks if it's a wg project
if [ -d ".workgraph" ]; then
    # 3. Executor TOML
    if [ ! -f ".workgraph/executors/amplifier.toml" ]; then
        ISSUES+=("Executor not installed (.workgraph/executors/amplifier.toml missing). Run setup.sh.")
    else
        # 4. Version check - use sed for portability (grep -oP is GNU-only)
        INSTALLED_VER=$(sed -n '1s/.*v\([0-9.]*\).*/\1/p' .workgraph/executors/amplifier.toml 2>/dev/null || echo "unknown")
        if [ "$INSTALLED_VER" != "$BUNDLE_VERSION" ]; then
            ISSUES+=("Executor version mismatch: installed v${INSTALLED_VER}, bundle v${BUNDLE_VERSION}. Run setup.sh to upgrade.")
        fi
    fi

    # 5. Wrapper script
    if [ ! -x ".workgraph/executors/amplifier-run.sh" ]; then
        ISSUES+=("amplifier-run.sh missing or not executable")
    fi

    # 6. Coordinator config
    if [ -f ".workgraph/config.toml" ]; then
        grep -q 'executor.*=.*"amplifier"' .workgraph/config.toml 2>/dev/null \
            || ISSUES+=("Amplifier not set as default executor (run: wg config --coordinator-executor amplifier)")
    fi
fi

# 7. Provider patch check (only if source override exists)
SETTINGS="$HOME/.amplifier/settings.yaml"
if [ -f "$SETTINGS" ]; then
    # Use grep/sed to extract provider-openai source from YAML (avoid PyYAML dependency)
    OVERRIDE=$(sed -n '/^sources:/,/^[^ ]/{
        /modules:/,/^[^ ]/{
            /provider-openai:/{ 
                s/.*provider-openai:[ "]*//
                s/[" ]*$//
                p
            }
        }
    }' "$SETTINGS" 2>/dev/null | head -1)

    if [ -n "$OVERRIDE" ] && [ -d "$OVERRIDE" ]; then
        CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
        if [ -n "$CACHE_DIR" ]; then
            SRC="$OVERRIDE/amplifier_module_provider_openai/__init__.py"
            DST="$CACHE_DIR/amplifier_module_provider_openai/__init__.py"
            if [ -f "$SRC" ] && [ -f "$DST" ]; then
                diff -q "$SRC" "$DST" &>/dev/null \
                    || ISSUES+=("Provider-openai cache out of sync with source override. Run: scripts/sync-provider-cache.sh")
            fi
        fi
    fi
fi

# Output
if [ ${#ISSUES[@]} -eq 0 ]; then
    exit 0  # All good, no context injection
fi

# Build warning message with proper JSON escaping
MSG="WORKGRAPH SETUP ISSUES:"
for issue in "${ISSUES[@]}"; do
    # Escape backslashes first, then quotes, then newlines for JSON
    escaped_issue="$issue"
    escaped_issue="${escaped_issue//\\/\\\\}"  # Escape backslashes
    escaped_issue="${escaped_issue//\"/\\\"}"   # Escape quotes
    escaped_issue="${escaped_issue//$'\n'/\\n}" # Escape newlines
    MSG="${MSG}\n  - ${escaped_issue}"
done

JSON_OUTPUT="{\"contextInjection\": \"${MSG}\"}"
printf '%s' "$JSON_OUTPUT"
exit 0
