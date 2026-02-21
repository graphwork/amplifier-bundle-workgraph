#!/usr/bin/env bash
# Amplifier executor wrapper for Workgraph.
# amplifier-bundle-workgraph v0.2.0
#
# Workgraph pipes the rendered prompt template via stdin.
# `amplifier run --mode single` requires the prompt as a positional argument.
# This wrapper bridges the gap.
#
# Usage (by workgraph -- do not call directly):
#   workgraph pipes prompt | bash amplifier-run.sh [--model MODEL] [EXTRA_FLAGS...]
#
# Workgraph may append flags like --model to the command. This script
# collects them before reading the prompt from stdin.
#
# Environment variables set by workgraph:
#   WG_TASK_ID  - task ID for the running task

set -euo pipefail

# Collect flags passed by workgraph (e.g. --model <name>)
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            # Skip "default" — let amplifier use its configured default model
            if [[ "$2" != "default" ]]; then
                EXTRA_ARGS+=("--model" "$2")
            fi
            shift 2
            ;;
        --model=*)
            _val="${1#--model=}"
            if [[ "$_val" != "default" ]]; then
                EXTRA_ARGS+=("--model" "$_val")
            fi
            shift
            ;;
        --bundle)
            EXTRA_ARGS+=("--bundle" "$2")
            shift 2
            ;;
        --bundle=*)
            EXTRA_ARGS+=("--bundle" "${1#--bundle=}")
            shift
            ;;
        *)
            # Forward any other flags as-is
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Read the full prompt from stdin (workgraph pipes the rendered template here)
PROMPT=$(cat)

if [[ -z "$PROMPT" ]]; then
    echo "Error: Empty prompt received from stdin" >&2
    exit 1
fi

# ARG_MAX guard: warn if prompt is very large
PROMPT_SIZE=${#PROMPT}
if [ "$PROMPT_SIZE" -gt 131072 ]; then
    echo "Warning: Prompt is ${PROMPT_SIZE} bytes (>128KB). May hit ARG_MAX limits." >&2
fi

# Execute amplifier in single (non-interactive) mode with the prompt as argument
exec amplifier run --mode single --output-format json "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" "$PROMPT"
