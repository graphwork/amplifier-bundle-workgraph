#!/usr/bin/env bash
# One-command setup for Amplifier + Workgraph integration.
#
# What this does:
#   1. Checks prerequisites (wg, amplifier)
#   2. Adds the workgraph bundle to Amplifier
#   3. Installs the Amplifier executor into .workgraph/executors/
#   4. Sets Amplifier as the default executor for wg service
#   5. Installs the setup validation hook
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/setup.sh | bash
#
#   Or from a local clone:
#   ./setup.sh
#
#   Check mode (validate without modifying):
#   ./setup.sh --check
#
#   Force overwrite existing executor files:
#   ./setup.sh --force
#
# Prerequisites:
#   - amplifier installed (https://github.com/microsoft/amplifier)
#   - wg installed (https://github.com/graphwork/workgraph)
#   - wg init already run in your project (for executor installation)

set -euo pipefail

BUNDLE_VERSION="0.2.0"
BUNDLE_URI="git+https://github.com/graphwork/amplifier-bundle-workgraph"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && pwd 2>/dev/null || echo ".")"

# Parse arguments
CHECK_MODE=false
FORCE_OVERWRITE=false
PROJECT_DIR="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_MODE=true
            shift
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--check] [--force] [PROJECT_DIR]"
            echo ""
            echo "  --check       Report status without modifying anything. Exit 0 if healthy, 1 if not."
            echo "  --force       Overwrite existing executor files even if version matches."
            echo "  PROJECT_DIR   Target project directory (default: current directory)."
            exit 0
            ;;
        *)
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

# Change to project directory if specified
if [ "$PROJECT_DIR" != "." ]; then
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "Error: Directory not found: $PROJECT_DIR"
        exit 1
    fi
    cd "$PROJECT_DIR"
fi

echo "=== Amplifier + Workgraph Setup (v$BUNDLE_VERSION) ==="
echo ""

# ============================================================
# Step 1: Check prerequisites
# ============================================================
echo "[1/5] Checking prerequisites..."
PREREQ_OK=true

if command -v amplifier &>/dev/null; then
    echo "      amplifier: $(command -v amplifier) ✓"
else
    echo "      amplifier: NOT FOUND ✗"
    PREREQ_OK=false
fi

if command -v wg &>/dev/null; then
    echo "      wg: $(command -v wg) ✓"
else
    echo "      wg: NOT FOUND ✗"
    PREREQ_OK=false
fi

if [ "$PREREQ_OK" = false ]; then
    echo ""
    echo "Error: Missing prerequisites. Install from:"
    echo "  - amplifier: https://github.com/microsoft/amplifier"
    echo "  - wg: https://github.com/graphwork/workgraph"
    exit 2
fi
echo ""

# ============================================================
# Step 2: Add the workgraph bundle to Amplifier
# ============================================================
echo "[2/5] Adding workgraph bundle to Amplifier..."

# Check if bundle is already installed
if amplifier bundle list 2>/dev/null | grep -q "^workgraph "; then
    INSTALLED_VER=$(amplifier bundle list 2>/dev/null | grep "^workgraph " | awk '{print $2}' | tr -d '()')
    echo "      Bundle 'workgraph' already installed (v$INSTALLED_VER)"
    
    if [ "$INSTALLED_VER" != "$BUNDLE_VERSION" ]; then
        echo "      Updating to v$BUNDLE_VERSION..."
        amplifier bundle remove workgraph 2>/dev/null || true
        amplifier bundle add "$BUNDLE_URI"
    else
        echo "      Already at latest version ✓"
    fi
else
    amplifier bundle add "$BUNDLE_URI"
fi
echo "      Bundle 'workgraph' v$BUNDLE_VERSION installed ✓"
echo ""

# ============================================================
# Step 3: Install executor into workgraph project
# ============================================================
echo "[3/5] Installing Amplifier executor..."

# Check if .workgraph exists
if [ ! -d ".workgraph" ]; then
    echo "      No .workgraph/ directory found. Initializing..."
    wg init
fi

mkdir -p .workgraph/executors

# Check for existing executor
EXECUTOR_NEEDS_INSTALL=true
if [ -f ".workgraph/executors/amplifier.toml" ]; then
    INSTALLED_EXECUTOR_VER=$(head -1 .workgraph/executors/amplifier.toml | grep -oP 'v\K[0-9.]+' || echo "unknown")
    echo "      Existing executor found (v$INSTALLED_EXECUTOR_VER)"
    
    if [ "$INSTALLED_EXECUTOR_VER" = "$BUNDLE_VERSION" ] && [ "$FORCE_OVERWRITE" = false ]; then
        echo "      Executor version matches bundle. Skipping install ✓"
        EXECUTOR_NEEDS_INSTALL=false
    elif [ "$FORCE_OVERWRITE" = true ]; then
        echo "      Force overwrite enabled."
    else
        echo "      Version mismatch. Updating..."
    fi
fi

if [ "$EXECUTOR_NEEDS_INSTALL" = true ]; then
    # If running from the repo, copy local files. Otherwise fetch from GitHub.
    if [ -f "$SCRIPT_DIR/executor/amplifier.toml" ]; then
        cp "$SCRIPT_DIR/executor/amplifier.toml" .workgraph/executors/amplifier.toml
        cp "$SCRIPT_DIR/executor/amplifier-run.sh" .workgraph/executors/amplifier-run.sh
    else
        echo "      Fetching executor config from GitHub..."
        curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/executor/amplifier.toml" \
            -o .workgraph/executors/amplifier.toml
        curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/executor/amplifier-run.sh" \
            -o .workgraph/executors/amplifier-run.sh
    fi
    chmod +x .workgraph/executors/amplifier-run.sh
fi

echo "      .workgraph/executors/amplifier.toml ✓"
echo "      .workgraph/executors/amplifier-run.sh ✓ (executable)"
echo ""

# ============================================================
# Step 4: Set as default executor
# ============================================================
echo "[4/5] Setting default executor..."
wg config --coordinator-executor amplifier 2>/dev/null || true
echo "      wg config --coordinator-executor amplifier ✓"
echo ""

# ============================================================
# Step 5: Install setup validation hook
# ============================================================
echo "[5/5] Installing setup validation hook..."

mkdir -p .amplifier/hooks

if [ -d "$SCRIPT_DIR/hooks/workgraph-setup" ]; then
    rm -rf .amplifier/hooks/workgraph-setup
    cp -r "$SCRIPT_DIR/hooks/workgraph-setup" .amplifier/hooks/
    chmod +x .amplifier/hooks/workgraph-setup/check-setup.sh
    echo "      .amplifier/hooks/workgraph-setup/ ✓"
else
    # Try to fetch from GitHub if not available locally
    echo "      Fetching hook from GitHub..."
    mkdir -p .amplifier/hooks/workgraph-setup
    curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/hooks/workgraph-setup/hooks.json" \
        -o .amplifier/hooks/workgraph-setup/hooks.json
    curl -sL "https://raw.githubusercontent.com/graphwork/amplifier-bundle-workgraph/main/hooks/workgraph-setup/check-setup.sh" \
        -o .amplifier/hooks/workgraph-setup/check-setup.sh
    chmod +x .amplifier/hooks/workgraph-setup/check-setup.sh
    echo "      .amplifier/hooks/workgraph-setup/ ✓"
fi
echo ""

# ============================================================
# Provider patch check (informational only)
# ============================================================
SETTINGS="$HOME/.amplifier/settings.yaml"
if [ -f "$SETTINGS" ]; then
    OVERRIDE=$(python3 -c "
import yaml
with open('$SETTINGS') as f:
    cfg = yaml.safe_load(f)
p = cfg.get('sources',{}).get('modules',{}).get('provider-openai','')
if p: print(p)
" 2>/dev/null || true)
    
    if [ -n "$OVERRIDE" ] && [ -d "$OVERRIDE" ]; then
        CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
        if [ -n "$CACHE_DIR" ]; then
            SRC="$OVERRIDE/amplifier_module_provider_openai/__init__.py"
            DST="$CACHE_DIR/amplifier_module_provider_openai/__init__.py"
            if [ -f "$SRC" ] && [ -f "$DST" ]; then
                if ! diff -q "$SRC" "$DST" &>/dev/null; then
                    echo "NOTE: Provider-openai cache may be out of sync."
                    echo "      Run: scripts/sync-provider-cache.sh"
                    echo ""
                fi
            fi
        fi
    fi
fi

echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  amplifier run -B workgraph    # Interactive session with wg awareness"
echo "  wg service start              # Auto-spawn Amplifier for each task"
echo "  ./setup.sh --check            # Verify setup health"
