#!/usr/bin/env bash
# One-command setup for Amplifier + Workgraph integration.
#
# What this does:
#   1. Adds the workgraph bundle to Amplifier (context, planner agent, behaviors)
#   2. Installs the Amplifier executor into .workgraph/executors/
#   3. Sets Amplifier as the default executor for wg service
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/setup.sh | bash
#
#   Or from a local clone:
#   ./setup.sh
#
# Prerequisites:
#   - amplifier installed (https://github.com/microsoft/amplifier)
#   - wg installed (https://github.com/graphwork/workgraph)
#   - wg init already run in your project

set -euo pipefail

BUNDLE_URI="git+https://github.com/graphwork/amplifier-bundle-workgraph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && pwd 2>/dev/null || echo ".")"

echo "=== Amplifier + Workgraph Setup ==="
echo ""

# Check prerequisites
if ! command -v amplifier &>/dev/null; then
    echo "Error: amplifier not found. Install from https://github.com/microsoft/amplifier"
    exit 1
fi

if ! command -v wg &>/dev/null; then
    echo "Error: wg not found. Install from https://github.com/graphwork/workgraph"
    exit 1
fi

# Step 1: Add the workgraph bundle to Amplifier
echo "[1/3] Adding workgraph bundle to Amplifier..."
if amplifier bundle list 2>/dev/null | grep -q workgraph; then
    echo "  Bundle 'workgraph' already installed, updating..."
    amplifier bundle remove workgraph 2>/dev/null || true
fi
amplifier bundle add "$BUNDLE_URI"
echo ""

# Step 2: Install executor into workgraph project
echo "[2/3] Installing Amplifier executor..."
if [ ! -d ".workgraph" ]; then
    echo "  No .workgraph/ directory found. Initializing..."
    wg init
fi

mkdir -p .workgraph/executors

# If running from the repo, copy local files. Otherwise fetch from GitHub.
if [ -f "$SCRIPT_DIR/executor/amplifier.toml" ]; then
    cp "$SCRIPT_DIR/executor/amplifier.toml" .workgraph/executors/amplifier.toml
    cp "$SCRIPT_DIR/executor/amplifier-run.sh" .workgraph/executors/amplifier-run.sh
else
    echo "  Fetching executor config from GitHub..."
    curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/executor/amplifier.toml" \
        -o .workgraph/executors/amplifier.toml
    curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/executor/amplifier-run.sh" \
        -o .workgraph/executors/amplifier-run.sh
fi
chmod +x .workgraph/executors/amplifier-run.sh
echo "  Installed to .workgraph/executors/"
echo ""

# Step 3: Set as default executor
echo "[3/3] Setting Amplifier as default executor..."
wg config --coordinator-executor amplifier
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  amplifier run -B workgraph    # Interactive session with wg awareness"
echo "  wg service start              # Auto-spawn Amplifier for each task"
echo "  wg add 'My task'              # Add work, service dispatches automatically"
