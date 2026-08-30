#!/bin/sh
# Builds the self-contained macOS app: PyInstaller (universal2) +
# Platypus wrap + Help Book registration (not exposed as a platypus
# CLI flag, so it runs as a separate post-processing step).

set -eu

cd "$(dirname "$0")/.."

ICON="macos-launcher/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "errore: icona non trovata in '$ICON'" >&2
    exit 1
fi

echo "== 1/4: PyInstaller (universal2) =="
.venv-build-macos/bin/pyinstaller \
    --name sbusta-p7m \
    --onefile \
    --target-arch universal2 \
    --paths . \
    --distpath build-macos/dist \
    --workpath build-macos/work \
    --specpath build-macos \
    --noconfirm \
    build-macos/entry.py

echo "== 2/4: rigenerazione indice di ricerca Help Book =="
( cd "macos-launcher/sbusta-p7m Help.help/Contents/Resources/it.lproj" && \
  hiutil -Cf "sbusta-p7m Help.helpindex" . )

echo "== 3/4: Platypus =="
platypus \
    -a "sbusta-p7m" \
    -o "None" \
    -p /bin/sh \
    -D \
    -X "p7m" \
    -f build-macos/dist/sbusta-p7m \
    -f "macos-launcher/sbusta-p7m Help.help" \
    -i "$ICON" \
    -u "TM-IA" \
    -V "0.1.0" \
    -I "com.tm-ia.sbusta-p7m" \
    -y \
    macos-launcher/wrapper.sh \
    build-macos/dist/sbusta-p7m.app

echo "== 4/4: registrazione Help Book in Info.plist =="
PLIST="build-macos/dist/sbusta-p7m.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleHelpBookFolder" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFBundleHelpBookName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleHelpBookFolder string 'sbusta-p7m Help.help'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleHelpBookName string 'com.tm-ia.sbusta-p7m.help'" "$PLIST"

echo "Fatto: build-macos/dist/sbusta-p7m.app"
