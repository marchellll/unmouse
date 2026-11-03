#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"
DIST="$ROOT/dist"
APP="$DIST/Unmouse.app"
ZIP="$DIST/Unmouse-$VERSION.zip"

IDENTITY_DEV="Apple Development: Marchell Imanuel (DY59WP772P)"
IDENTITY_ID=$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application/ {print $2; exit}')

if [[ -z "${IDENTITY_ID:-}" ]]; then
  echo "Missing Developer ID Application certificate for team DY59WP772P."
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates."
  echo "Falling back to Apple Development for a local signed build only (not for notarization)."
  IDENTITY="$IDENTITY_DEV"
  NOTARIZE=0
else
  IDENTITY="$IDENTITY_ID"
  NOTARIZE=1
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Unmouse"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Unmouse"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"

codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

if [[ "$NOTARIZE" -eq 1 ]]; then
  if ! xcrun notarytool history --keychain-profile "notarytool" >/dev/null 2>&1; then
    echo "Missing notarytool keychain profile 'notarytool'."
    echo "Run: xcrun notarytool store-credentials notarytool --apple-id EMAIL --team-id DY59WP772P --password APP_SPECIFIC_PASSWORD"
    exit 1
  fi
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "notarytool" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarized $ZIP"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Built $ZIP (Development signature; not notarized)"
fi
