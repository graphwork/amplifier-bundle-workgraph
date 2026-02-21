#!/usr/bin/env bash
# Sync provider-openai source override to Amplifier cache.
# Run this after `amplifier update` if you use a patched provider.
#
# This script detects if you have a source override for provider-openai in
# ~/.amplifier/settings.yaml and syncs it to the cached module.

set -euo pipefail

SETTINGS="$HOME/.amplifier/settings.yaml"

# Check if settings.yaml exists
if [ ! -f "$SETTINGS" ]; then
    echo "No ~/.amplifier/settings.yaml found. No source overrides configured."
    exit 0
fi

# Read source override path from settings
SOURCE_PATH=$(python3 -c "
import yaml
with open('$SETTINGS') as f:
    cfg = yaml.safe_load(f)
p = cfg.get('sources',{}).get('modules',{}).get('provider-openai','')
if p: print(p)
" 2>/dev/null)

if [ -z "$SOURCE_PATH" ]; then
    echo "No source override for provider-openai in ~/.amplifier/settings.yaml"
    exit 0
fi

# Check if source path exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Source override path does not exist: $SOURCE_PATH"
    exit 1
fi

# Find cached provider-openai module
CACHE_DIR=$(ls -d "$HOME/.amplifier/cache/amplifier-module-provider-openai-"*/ 2>/dev/null | head -1)
if [ -z "$CACHE_DIR" ]; then
    echo "No cached provider-openai module found in ~/.amplifier/cache/"
    exit 1
fi

SRC="$SOURCE_PATH/amplifier_module_provider_openai/__init__.py"
DST="$CACHE_DIR/amplifier_module_provider_openai/__init__.py"

# Check if both files exist
if [ ! -f "$SRC" ]; then
    echo "Source file not found: $SRC"
    exit 1
fi

if [ ! -f "$DST" ]; then
    echo "Cache file not found: $DST"
    exit 1
fi

# Check if they differ
if diff -q "$SRC" "$DST" &>/dev/null; then
    echo "Cache already matches source override. No sync needed."
    exit 0
fi

echo "Syncing provider-openai:"
echo "  Source: $SRC"
echo "  Cache:  $DST"
cp "$SRC" "$DST"
echo "Done"
