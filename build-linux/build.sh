#!/bin/sh
# Builds the self-contained Linux tarball (PyInstaller, native arch).
# Meant to run on the target architecture itself (no cross-compiling
# with PyInstaller): x86_64 and aarch64 need two separate runs, on
# matching machines/runners — see .github/workflows/build-linux.yml

set -eu

cd "$(dirname "$0")/.."

ARCH=$(uname -m)

echo "== 1/4: dipendenze di build =="
python3 -m venv build-linux/.venv
build-linux/.venv/bin/pip install --upgrade pip >/dev/null
build-linux/.venv/bin/pip install asn1crypto pyinstaller

echo "== 2/4: PyInstaller ($ARCH) =="
build-linux/.venv/bin/pyinstaller \
    --name sbusta-p7m-cli \
    --onefile \
    --paths . \
    --distpath build-linux/dist \
    --workpath build-linux/work \
    --specpath build-linux \
    --noconfirm \
    build-linux/entry.py

echo "== 3/4: icona (SVG -> PNG) =="
if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 256 -h 256 linux-launcher/icon.svg -o build-linux/dist/icon.png
elif command -v convert >/dev/null 2>&1; then
    convert -background none -resize 256x256 linux-launcher/icon.svg build-linux/dist/icon.png
else
    echo "errore: nessun convertitore SVG->PNG trovato (rsvg-convert o imagemagick)" >&2
    exit 1
fi

echo "== 4/4: pacchetto =="
PKG="sbusta-p7m-linux-$ARCH"
STAGE="build-linux/dist/$PKG"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp build-linux/dist/sbusta-p7m-cli "$STAGE/"
cp linux-launcher/wrapper.sh "$STAGE/"
cp -r linux-launcher/help "$STAGE/"
cp linux-launcher/sbusta-p7m.desktop "$STAGE/"
cp linux-launcher/install.sh "$STAGE/"
cp linux-launcher/uninstall.sh "$STAGE/"
cp build-linux/dist/icon.png "$STAGE/"
chmod +x "$STAGE/wrapper.sh" "$STAGE/sbusta-p7m-cli" "$STAGE/install.sh" "$STAGE/uninstall.sh"

tar -C build-linux/dist -czf "build-linux/dist/$PKG.tar.gz" "$PKG"

echo "Fatto: build-linux/dist/$PKG.tar.gz"
