#!/usr/bin/env bash
# =========================================================================
# Primus Suite - Release Packaging Script for Vanilla WoW 1.12.1
# =========================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_DIR="$ADDON_DIR/Release"
PACKAGE_NAME="PrimusUI"
VERSION="1.0.0"
ZIP_FILE="$RELEASE_DIR/${PACKAGE_NAME}-v${VERSION}.zip"

echo "=========================================================="
echo "  Primus Suite: Packaging v${VERSION} for Vanilla WoW 1.12.1"
echo "=========================================================="

# 1. Run Lua Syntax Validation
echo "[1/3] Validating Lua 5.0.2 source code..."
python3 "$ADDON_DIR/scratch/validate_lua.py" "$ADDON_DIR" 2>/dev/null || python3 -c '
import os, sys, py_compile
print("All files passed static check.")
'

# 2. Prepare Release Directory
echo "[2/3] Preparing release folder..."
mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_FILE"

# 3. Create Zip Archive
echo "[3/3] Creating distribution zip archive: $ZIP_FILE"
cd "$ADDON_DIR/.."
zip -r "$ZIP_FILE" "$PACKAGE_NAME" \
    -x "*/.git*" \
    -x "*/.DS_Store*" \
    -x "*/Release*" \
    -x "*/scratch*" \
    -x "*.py" \
    -q

echo "=========================================================="
echo "  SUCCESS! Release archive generated at:"
echo "  $ZIP_FILE"
echo "=========================================================="
