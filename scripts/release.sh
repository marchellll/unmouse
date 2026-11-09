#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLIST="$ROOT/Support/Info.plist"

plist_string() {
  local file="$1" key="$2" value
  value="$(awk -v key="$key" '
    $0 ~ "<key>" key "</key>" {
      if (getline && match($0, /<string>[^<]*<\/string>/)) {
        print substr($0, RSTART + 8, RLENGTH - 17)
        exit
      }
    }
  ' "$file")"
  if [[ -z "$value" ]]; then
    echo "Missing $key in $file" >&2
    return 1
  fi
  printf '%s' "$value"
}

# ponytail: edit the two <string> lines in place. PlistBuddy rewrites the file and reorders keys.
plist_set() {
  local file="$1" key="$2" value="$3" tmp mode
  mode="$(stat -f %A "$file")"
  tmp="$(mktemp)"
  if ! awk -v key="$key" -v value="$value" '
    $0 ~ "<key>" key "</key>" {
      print
      if (!getline) exit 1
      if ($0 ~ /^[[:space:]]*<string>.*<\/string>[[:space:]]*$/) {
        match($0, /^[[:space:]]*/)
        print substr($0, RSTART, RLENGTH) "<string>" value "</string>"
        found = 1
        next
      }
      exit 1
    }
    { print }
    END { if (!found) exit 1 }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    echo "Could not set $key in $file" >&2
    return 1
  fi
  mv "$tmp" "$file"
  chmod "$mode" "$file"
}

bump_plist() {
  local file="$1" version="$2" build
  build="$(plist_string "$file" CFBundleVersion)"
  if [[ ! "$build" =~ ^[0-9]+$ ]]; then
    echo "CFBundleVersion in $file must be an integer (found '$build')." >&2
    return 1
  fi
  plist_set "$file" CFBundleShortVersionString "$version"
  plist_set "$file" CFBundleVersion "$((build + 1))"
}

bump_patch() {
  local major minor patch
  IFS=. read -r major minor patch <<< "$1"
  printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

# Next short version is the plist value, or the next free patch when that tag exists.
next_version() {
  local version="$1" taken advanced
  shift
  advanced=1
  while [[ "$advanced" -eq 1 ]]; do
    advanced=0
    for taken in "$@"; do
      if [[ "$taken" == "$version" ]]; then
        version="$(bump_patch "$version")"
        advanced=1
        break
      fi
    done
  done
  printf '%s' "$version"
}

collect_tags() {
  local remote="$1" tag line listing
  while IFS= read -r tag; do
    [[ -n "$tag" ]] && printf '%s\n' "${tag#v}"
  done < <(git tag -l 'v*')
  if [[ "$remote" -eq 1 ]]; then
    listing="$(git ls-remote --tags origin 'refs/tags/v*')" || exit 1
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      tag="${line##*refs/tags/}"
      [[ "$tag" == *'^'* ]] && continue
      printf '%s\n' "${tag#v}"
    done <<< "$listing"
  fi
}

if [[ "${1:-}" == "--self-check" ]]; then
  tmp="$(mktemp)"
  cp "$PLIST" "$tmp"
  build="$(plist_string "$tmp" CFBundleVersion)"
  before="$(awk '
    /<key>NSHumanReadableCopyright<\/key>/ { print "copy" }
    /<key>NSAccessibilityUsageDescription<\/key>/ { print "access" }
  ' "$tmp")"
  [[ "$(next_version 0.1.0)" == "0.1.0" ]]
  [[ "$(next_version 0.1.0 0.1.0)" == "0.1.1" ]]
  [[ "$(next_version 0.1.0 0.1.0 0.1.1)" == "0.1.2" ]]
  [[ "$(bump_patch 1.2.9)" == "1.2.10" ]]
  bump_plist "$tmp" "9.9.9"
  [[ "$(plist_string "$tmp" CFBundleShortVersionString)" == "9.9.9" ]]
  [[ "$(plist_string "$tmp" CFBundleVersion)" == "$((build + 1))" ]]
  after="$(awk '
    /<key>NSHumanReadableCopyright<\/key>/ { print "copy" }
    /<key>NSAccessibilityUsageDescription<\/key>/ { print "access" }
  ' "$tmp")"
  [[ "$before" == "$after" ]]
  rm -f "$tmp"
  echo "ok"
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "usage: scripts/release.sh"
  exit 1
fi

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
  echo "Falling back to Apple Development (local zip only; leaves git unchanged)."
  IDENTITY="$IDENTITY_DEV"
  NOTARIZE=0
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit or stash before releasing."
    exit 1
  fi
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "Missing notarytool keychain profile '$NOTARY_PROFILE'."
    echo "Store credentials in the keychain (not in git), e.g.:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE"
    exit 1
  fi
fi

CURRENT="$(plist_string "$PLIST" CFBundleShortVersionString)"
if [[ ! "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "CFBundleShortVersionString must be MAJOR.MINOR.PATCH (found '$CURRENT')."
  exit 1
fi
tags_file="$(mktemp)"
collect_tags "$NOTARIZE" > "$tags_file"
# shellcheck disable=SC2046
VERSION="$(next_version "$CURRENT" $(cat "$tags_file"))"
rm -f "$tags_file"
TAG="v$VERSION"
DIST="$ROOT/dist"
APP="$DIST/Unmouse.app"
ZIP="$DIST/Unmouse-$VERSION.zip"
echo "Release $TAG"

if [[ "$NOTARIZE" -eq 1 ]]; then
  STAGED_PLIST="$(mktemp)"
  cp "$PLIST" "$STAGED_PLIST"
  bump_plist "$STAGED_PLIST" "$VERSION"
  echo "Version $VERSION (build $(plist_string "$STAGED_PLIST" CFBundleVersion))"
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Unmouse"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Unmouse"
if [[ "$NOTARIZE" -eq 1 ]]; then
  cp "$STAGED_PLIST" "$APP/Contents/Info.plist"
else
  cp "$PLIST" "$APP/Contents/Info.plist"
  plist_set "$APP/Contents/Info.plist" CFBundleShortVersionString "$VERSION"
fi
cp -R "$ROOT/configs-example" "$APP/Contents/Resources/configs-example"

got="$(plist_string "$APP/Contents/Info.plist" CFBundleShortVersionString)"
if [[ "$got" != "$VERSION" ]]; then
  echo "Bundle version is $got, expected $VERSION."
  exit 1
fi

codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"

if [[ "$NOTARIZE" -eq 1 ]]; then
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun stapler validate "$APP"
  spctl -a -vv "$APP"
  cp "$STAGED_PLIST" "$PLIST"
  git add -- "$PLIST"
  git commit -m "release: $TAG"
  git push origin HEAD
  git tag "$TAG"
  git push origin "$TAG"
  echo "Released $TAG ($ZIP)"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Built $ZIP (Development signature; not notarized)"
fi
