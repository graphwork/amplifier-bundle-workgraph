#!/usr/bin/env bash
# Amplifier executor wrapper for Workgraph.
#
# Workgraph pipes the rendered prompt template via stdin.
# `amplifier run --mode single` requires the prompt as a positional argument.
# This wrapper bridges the gap.
#
# Usage (by workgraph -- do not call directly):
#   workgraph pipes prompt | bash amplifier-run.sh
#
# Environment variables set by workgraph:
#   WG_TASK_ID  - task ID for the running task

set -euo pipefail

# Read the full prompt from stdin (workgraph pipes the rendered template here)
PROMPT=$(cat)

if [[ -z "$PROMPT" ]]; then
    echo "Error: Empty prompt received from stdin" >&2
    exit 1
fi

# Execute amplifier in single (non-interactive) mode with the prompt as argument
exec amplifier run --mode single --output-format json "$PROMPT"
