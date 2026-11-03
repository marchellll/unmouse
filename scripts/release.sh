#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"
DIST="$ROOT/dist"
APP="$DIST/Unmouse.app"
ZIP="$DIST/Unmouse-$VERSION.zip"

# Optional local config (gitignored): signing.env with UNMOUSE_* vars only.
# Never put passwords or .p12 paths into the repo.
if [[ -f "$ROOT/signing.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/signing.env"
fi

NOTARY_PROFILE="${UNMOUSE_NOTARY_PROFILE:-notarytool}"

IDENTITY_DEV="${UNMOUSE_CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY_DEV" ]]; then
  IDENTITY_DEV=$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
fi

IDENTITY_ID="${UNMOUSE_DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$IDENTITY_ID" ]]; then
  IDENTITY_ID=$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi

if [[ -n "$IDENTITY_ID" ]]; then
  IDENTITY="$IDENTITY_ID"
  NOTARIZE=1
else
  if [[ -z "$IDENTITY_DEV" ]]; then
    echo "No codesigning identity found. Set UNMOUSE_DEVELOPER_ID_IDENTITY or UNMOUSE_CODESIGN_IDENTITY."
    exit 1
  fi
  echo "No Developer ID Application identity in the keychain."
  echo "Falling back to Apple Development (local only; not for notarization)."
  IDENTITY="$IDENTITY_DEV"
  NOTARIZE=0
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Unmouse"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Unmouse"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"
for bundle in Unmouse_Unmouse.bundle Unmouse_UnmouseCore.bundle; do
  if [[ -d "$BIN_DIR/$bundle" ]]; then
    cp -R "$BIN_DIR/$bundle" "$APP/Contents/Resources/"
  fi
done

codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

if [[ "$NOTARIZE" -eq 1 ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing notarytool keychain profile '$NOTARY_PROFILE'."
    echo "Store credentials in the keychain (not in git), e.g.:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE"
    exit 1
  fi
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarized $ZIP"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Built $ZIP (Development signature; not notarized)"
fi
