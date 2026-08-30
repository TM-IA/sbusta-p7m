#!/bin/sh
# Per-user install (no root needed): copies files, registers the
# .desktop entry.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR="$HOME/.local/share/sbusta-p7m"
BIN_DIR="$HOME/.local/bin"

if [ ! -f "$SCRIPT_DIR/sbusta-p7m" ]; then
    echo "errore: sbusta-p7m non trovato accanto a install.sh." >&2
    echo "Questo script va eseguito dal pacchetto estratto (sbusta-p7m-linux-<arch>.tar.gz)," >&2
    echo "non dalla cartella sorgente linux-launcher/. Vedi README.md, sezione Linux." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
cp "$SCRIPT_DIR/sbusta-p7m" "$BIN_DIR/"
cp "$SCRIPT_DIR/wrapper.sh" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/help" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/icon.png" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/uninstall.sh" "$INSTALL_DIR/"
chmod +x "$BIN_DIR/sbusta-p7m" "$INSTALL_DIR/wrapper.sh" "$INSTALL_DIR/uninstall.sh"

mkdir -p "$HOME/.local/share/applications"
sed "s#__INSTALL_DIR__#$INSTALL_DIR#g" "$SCRIPT_DIR/sbusta-p7m.desktop" \
    > "$HOME/.local/share/applications/sbusta-p7m.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

echo "Installato in: $INSTALL_DIR"
echo "Comando da terminale: $BIN_DIR/sbusta-p7m"
echo "Voce menu applicazioni: $HOME/.local/share/applications/sbusta-p7m.desktop"
echo "Per disinstallare: $INSTALL_DIR/uninstall.sh"
