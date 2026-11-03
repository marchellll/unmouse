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

BIN="$(swift build -c release --show-bin-path)/Unmouse"
APP="$ROOT/Unmouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Unmouse"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"

codesign --force --deep --sign "$IDENTITY" "$APP"

echo "Built $APP (signed with: $IDENTITY)"
