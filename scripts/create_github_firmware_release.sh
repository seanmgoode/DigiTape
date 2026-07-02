#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-seanmgoode/DigiTape}"
TAG="${TAG:-firmware-v3.2.1}"
TITLE="${TITLE:-DigiTape Firmware 3.2.1}"
ROOT="${ROOT:-/Users/seangoode/Documents/DigiTape/App/data/DigiTape_iOS_Controller_2.0.2}"
FIRMWARE_DIR="$ROOT/docs/firmware"
PACKAGE="${PACKAGE:-$FIRMWARE_DIR/packages/digitape_firmware_20260702_123830}"
GH_BIN="${GH_BIN:-gh}"

LATEST_JSON="$FIRMWARE_DIR/latest.json"
PACKAGE_MANIFEST="$PACKAGE/manifest.json"
MINI_BIN="$PACKAGE/minirx18/MiniRX1.0.ino.bin"
RX241_BIN="$PACKAGE/rx241/MiniRX2.41.ino.bin"
TX_BIN="$PACKAGE/tx/DigiTape_TX_2_0_4.ino.bin"

for file in "$LATEST_JSON" "$PACKAGE_MANIFEST" "$MINI_BIN" "$RX241_BIN" "$TX_BIN"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing release asset: $file"
    exit 1
  fi
done

if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not logged in. Run: gh auth login"
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cp "$LATEST_JSON" "$tmpdir/firmware-manifest.json"
cp "$PACKAGE_MANIFEST" "$tmpdir/package-manifest.json"
cp "$MINI_BIN" "$tmpdir/MiniRX1.0.ino.bin"
cp "$RX241_BIN" "$tmpdir/MiniRX2.41.ino.bin"
cp "$TX_BIN" "$tmpdir/DigiTape_TX_2_0_4.ino.bin"

notes="$tmpdir/release-notes.md"
cat > "$notes" <<'NOTES'
DigiTape firmware package 3.2.1.

Includes:
- MiniRx 1.8 AMOLED firmware
- RX 2.41 AMOLED firmware
- DigiTape TX / Proto1 firmware
- firmware-manifest.json for the app/OTA updater
- package-manifest.json with package-level metadata

The app verifies firmware size and SHA-256 before OTA.
NOTES

if "$GH_BIN" release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  "$GH_BIN" release upload "$TAG" \
    "$tmpdir/firmware-manifest.json" \
    "$tmpdir/package-manifest.json" \
    "$tmpdir/MiniRX1.0.ino.bin" \
    "$tmpdir/MiniRX2.41.ino.bin" \
    "$tmpdir/DigiTape_TX_2_0_4.ino.bin" \
    --repo "$REPO" \
    --clobber
else
  "$GH_BIN" release create "$TAG" \
    "$tmpdir/firmware-manifest.json" \
    "$tmpdir/package-manifest.json" \
    "$tmpdir/MiniRX1.0.ino.bin" \
    "$tmpdir/MiniRX2.41.ino.bin" \
    "$tmpdir/DigiTape_TX_2_0_4.ino.bin" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes-file "$notes" \
    --latest
fi

echo "Release ready:"
echo "https://github.com/$REPO/releases/tag/$TAG"
