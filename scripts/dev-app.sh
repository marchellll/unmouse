#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release

BIN="$(swift build -c release --show-bin-path)/Unmouse"
APP="$ROOT/Unmouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Unmouse"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"

IDENTITY="Apple Development: Marchell Imanuel (DY59WP772P)"
codesign --force --deep --sign "$IDENTITY" "$APP"

echo "Built $APP"
