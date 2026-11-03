#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Optional: export UNMOUSE_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
IDENTITY="${UNMOUSE_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
fi
if [[ -z "$IDENTITY" ]]; then
  echo "No Apple Development identity found. Set UNMOUSE_CODESIGN_IDENTITY or install a cert."
  exit 1
fi

swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Unmouse"
APP="$ROOT/Unmouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Unmouse"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"

# SPM resource bundles (required if anything touches Bundle.module)
for bundle in Unmouse_Unmouse.bundle Unmouse_UnmouseCore.bundle; do
  if [[ -d "$BIN_DIR/$bundle" ]]; then
    cp -R "$BIN_DIR/$bundle" "$APP/Contents/Resources/"
  fi
done

codesign --force --deep --sign "$IDENTITY" "$APP"

echo "Built $APP (signed with: $IDENTITY)"
