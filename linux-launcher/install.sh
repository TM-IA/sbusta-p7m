#!/bin/sh
# Per-user install (no root needed): copies files, registers the
# .desktop entry.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR="$HOME/.local/share/sbusta-p7m"

mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/sbusta-p7m-cli" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/wrapper.sh" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/help" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/icon.png" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/wrapper.sh" "$INSTALL_DIR/sbusta-p7m-cli" "$INSTALL_DIR/uninstall.sh"

mkdir -p "$HOME/.local/share/applications"
sed "s#__INSTALL_DIR__#$INSTALL_DIR#g" "$SCRIPT_DIR/sbusta-p7m.desktop" \
    > "$HOME/.local/share/applications/sbusta-p7m.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

echo "Installato in: $INSTALL_DIR"
echo "Voce menu applicazioni: $HOME/.local/share/applications/sbusta-p7m.desktop"
echo "Per disinstallare: $INSTALL_DIR/uninstall.sh"
