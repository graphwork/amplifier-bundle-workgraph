#!/usr/bin/env bash
# Amplifier executor wrapper for Workgraph.
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
            EXTRA_ARGS+=("--model" "$2")
            shift 2
            ;;
        --model=*)
            EXTRA_ARGS+=("--model" "${1#--model=}")
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

# Execute amplifier in single (non-interactive) mode with the prompt as argument
exec amplifier run --mode single --output-format json "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" "$PROMPT"
