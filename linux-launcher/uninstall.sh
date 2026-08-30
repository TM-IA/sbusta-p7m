#!/bin/sh
# Removes what install.sh created, nothing else.

set -eu

INSTALL_DIR="$HOME/.local/share/sbusta-p7m"
BIN_FILE="$HOME/.local/bin/sbusta-p7m"
DESKTOP_FILE="$HOME/.local/share/applications/sbusta-p7m.desktop"

rm -rf "$INSTALL_DIR"
rm -f "$BIN_FILE"
rm -f "$DESKTOP_FILE"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

echo "Rimosso: $INSTALL_DIR"
echo "Rimosso: $BIN_FILE"
echo "Rimosso: $DESKTOP_FILE"
