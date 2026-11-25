#!/usr/bin/env bash
#
# Builds, signs, notarizes, and packages a DockDivider release.
#
# Required for a real release:
#   NOTARY_PROFILE   Keychain profile created with
#                    xcrun notarytool store-credentials
#
# Optional:
#   SIGNING_IDENTITY  "Developer ID Application: Name (TEAM)"
#                     (auto-detected from the keychain when omitted)
#   DEVELOPMENT_TEAM  Apple team ID. Required unless the project sets one.
#   RELEASE_VERSION   Overrides MARKETING_VERSION
#   BUILD_NUMBER      Overrides CURRENT_PROJECT_VERSION
#   NOTARIZE=0        Skip notarization for a local signed dry run
#   SCHEME            Defaults to DockDivider
#
# The script never commits, tags, or uploads anything. See docs/RELEASE.md.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-DockDivider}"
PROJECT="DockDivider.xcodeproj"
CONFIGURATION="Release"
NOTARIZE="${NOTARIZE:-1}"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '==> %s\n' "$*"; }

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found. Install Xcode."
command -v codesign >/dev/null 2>&1 || fail "codesign not found."
command -v hdiutil >/dev/null 2>&1 || fail "hdiutil not found."
[[ -d "$PROJECT" ]] || fail "Run this from the repository root (missing $PROJECT)."

# xcode-select may point at Command Line Tools rather than a full Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcodebuild -version >/dev/null 2>&1 \
  || fail "xcodebuild requires a full Xcode install. Set DEVELOPER_DIR."

SETTINGS="$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -showBuildSettings 2>/dev/null)"
setting() {
  printf '%s\n' "$SETTINGS" | awk -F' = ' -v key="$1" '$1 ~ "^ *" key "$" { print $2; exit }'
}

VERSION="${RELEASE_VERSION:-$(setting MARKETING_VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(setting CURRENT_PROJECT_VERSION)}"
TEAM_ID="${DEVELOPMENT_TEAM:-$(setting DEVELOPMENT_TEAM)}"

[[ -n "$VERSION" ]] || fail "Could not read MARKETING_VERSION."
[[ -n "$BUILD_NUMBER" ]] || fail "Could not read CURRENT_PROJECT_VERSION."
[[ -n "$TEAM_ID" ]] || fail "Set DEVELOPMENT_TEAM (the project intentionally ships without one)."

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' \
      | head -n 1
  )"
fi
[[ -n "${SIGNING_IDENTITY:-}" ]] || fail "No 'Developer ID Application' identity found. Set SIGNING_IDENTITY."

if [[ "$NOTARIZE" == "1" && -z "${NOTARY_PROFILE:-}" ]]; then
  fail "Set NOTARY_PROFILE (xcrun notarytool store-credentials ...) or run with NOTARIZE=0."
fi

note "Version $VERSION ($BUILD_NUMBER)"
note "Team $TEAM_ID"
note "Identity $SIGNING_IDENTITY"

if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
  printf 'warning: working tree has uncommitted changes; the artifact will not match HEAD.\n' >&2
fi

OUT="$ROOT/build/release/$VERSION"
ARCHIVE="$OUT/DockDivider.xcarchive"
APP="$OUT/DockDivider.app"
ZIP="$OUT/DockDivider-$VERSION.zip"
DMG="$OUT/DockDivider-$VERSION.dmg"

rm -rf "$OUT"
mkdir -p "$OUT"

note "Archiving"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  archive \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/DockDivider.app"
[[ -d "$APP_IN_ARCHIVE" ]] || fail "Archive did not contain DockDivider.app."
ditto "$APP_IN_ARCHIVE" "$APP"
xattr -cr "$APP"

note "Signing app"
RUNNER="$APP/Contents/Resources/divider_runner"
if [[ -f "$RUNNER" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$RUNNER"
fi
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"

note "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^/    /p'

if [[ "$NOTARIZE" == "1" ]]; then
  note "Notarizing app"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv "$APP"
fi

note "Creating DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/DockDivider.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "DockDivider" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

if [[ "$NOTARIZE" == "1" ]]; then
  note "Notarizing DMG"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
fi

shasum -a 256 "$DMG" > "$DMG.sha256"

note "Artifacts"
printf '    %s\n' "$DMG" "$DMG.sha256"
if [[ -f "$ZIP" ]]; then
  printf '    %s\n' "$ZIP"
fi

if [[ "$NOTARIZE" != "1" ]]; then
  printf 'warning: notarization skipped (NOTARIZE=0). The artifact is signed but not notarized.\n' >&2
fi
