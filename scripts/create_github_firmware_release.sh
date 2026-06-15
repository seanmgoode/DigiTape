#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-seanmgoode/DigiTape}"
TAG="${TAG:-v2.1}"
TITLE="${TITLE:-DigiTape Firmware v2.1}"
ROOT="${ROOT:-/Users/seangoode/Documents/DigiTape}"
APP_DIR="${APP_DIR:-$ROOT/App/data/DigiTape_iOS_Controller_2.0.2}"

RX_BIN="$ROOT/Digitape Current INOs/DigiTape_RX_2_0_9_Touch28_Test/release/ota-update/INSTALL_DigiTape_RX_2_1.ino.bin"
TX_BIN="$ROOT/Digitape Current INOs/DigiTape_TX_2_0_4/release/ota-update/INSTALL_DigiTape_TX_2_1.ino.bin"
MANIFEST="$APP_DIR/docs/firmware-manifest.github-v2.1.json"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Set GITHUB_TOKEN with repo release permission first."
  exit 1
fi

for file in "$RX_BIN" "$TX_BIN" "$MANIFEST"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing release asset: $file"
    exit 1
  fi
done

api="https://api.github.com/repos/$REPO/releases"
release_json="$(mktemp)"

status="$(
  curl -sS -o "$release_json" -w "%{http_code}" \
    -X POST "$api" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -d @- <<JSON
{
  "tag_name": "$TAG",
  "name": "$TITLE",
  "body": "DigiTape firmware release. Upload includes RX/TX OTA .ino.bin files and firmware-manifest.json for the iOS app cloud updater.",
  "draft": false,
  "prerelease": false
}
JSON
)"

if [[ "$status" != "201" ]]; then
  echo "GitHub release create failed with HTTP $status"
  cat "$release_json"
  exit 1
fi

upload_url="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("upload_url").sub(/\{.*\}/, "")' "$release_json")"

upload_asset() {
  local path="$1"
  local name="$2"
  local type="$3"
  local output
  output="$(mktemp)"
  local code
  code="$(
    curl -sS -o "$output" -w "%{http_code}" \
      -X POST "$upload_url?name=$name" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: $type" \
      --data-binary @"$path"
  )"
  if [[ "$code" != "201" ]]; then
    echo "Upload failed for $name with HTTP $code"
    cat "$output"
    exit 1
  fi
  echo "Uploaded $name"
}

upload_asset "$RX_BIN" "INSTALL_DigiTape_RX_2_1.ino.bin" "application/octet-stream"
upload_asset "$TX_BIN" "INSTALL_DigiTape_TX_2_1.ino.bin" "application/octet-stream"
upload_asset "$MANIFEST" "firmware-manifest.json" "application/json"

echo "Release ready:"
echo "https://github.com/$REPO/releases/tag/$TAG"
