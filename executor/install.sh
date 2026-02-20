#!/usr/bin/env bash
# Install the Amplifier executor into a workgraph project.
#
# Usage:
#   ./install.sh [project-dir]
#
# If project-dir is omitted, uses the current directory.
# The directory must contain a .workgraph/ folder (run `wg init` first).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-.}"

# Resolve to absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Verify workgraph is initialized
if [ ! -d "$PROJECT_DIR/.workgraph" ]; then
    echo "Error: No .workgraph/ directory found in $PROJECT_DIR"
    echo "Run 'wg init' first to initialize a workgraph project."
    exit 1
fi

# Create executors directory if needed
mkdir -p "$PROJECT_DIR/.workgraph/executors"

# Copy executor config and wrapper script
cp "$SCRIPT_DIR/amplifier.toml" "$PROJECT_DIR/.workgraph/executors/amplifier.toml"
cp "$SCRIPT_DIR/amplifier-run.sh" "$PROJECT_DIR/.workgraph/executors/amplifier-run.sh"
chmod +x "$PROJECT_DIR/.workgraph/executors/amplifier-run.sh"

echo "Installed Amplifier executor to $PROJECT_DIR/.workgraph/executors/amplifier.toml"
echo ""
echo "To set as default executor:"
echo "  cd $PROJECT_DIR && wg config --coordinator-executor amplifier"
echo ""
echo "To use for a single spawn:"
echo "  wg spawn <TASK_ID> --executor amplifier"
