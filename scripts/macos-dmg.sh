#!/usr/bin/env bash
# Builds the macOS app, signs it with a given certificate and provisioning profiles,
# and packages it as a DMG. Used by .github/workflows/release.yml; also runs locally.
#
# Required environment:
#   VERSION         Marketing version, e.g. 1.2.0
#   SIGN_IDENTITY   Signing identity in the keychain (SHA-1 or full name)
#   APP_PROFILE     Path to the provisioning profile for com.oktayibis.awgconnect.mac
#   TUNNEL_PROFILE  Path to the provisioning profile for com.oktayibis.awgconnect.mac.tunnel
# Optional:
#   BUILD_NUMBER    CFBundleVersion (default: 1)
#   OUTPUT_DIR      Where the DMG is written (default: ./dist)
#   KEYCHAIN        Keychain that holds SIGN_IDENTITY (default: the search list)
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                   App Store Connect API key; when set, the DMG is notarized and stapled.
#                   Only meaningful for a Developer ID certificate.
set -euo pipefail

: "${VERSION:?}" "${SIGN_IDENTITY:?}" "${APP_PROFILE:?}" "${TUNNEL_PROFILE:?}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP_NAME="AWG Connect"
DMG="$OUTPUT_DIR/AWGConnect-$VERSION-macos.dmg"
KEYCHAIN_ARGS=()
[[ -n "${KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")

profile_value() { # profile, plist key path
    security cms -D -i "$1" | plutil -extract "$2" raw -o - -
}

TEAM_ID="$(profile_value "$APP_PROFILE" TeamIdentifier.0)"
for p in "$APP_PROFILE" "$TUNNEL_PROFILE"; do
    expiry="$(profile_value "$p" ExpirationDate)"
    echo "Profile $(profile_value "$p" Name) (team $TEAM_ID) expires $expiry"
done

echo "==> Archiving (unsigned)"
xcodebuild archive \
    -project "$ROOT/AmneziaClient.xcodeproj" \
    -scheme AmneziaMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$WORK/AWGConnect.xcarchive" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    | grep -E '^(\*\*|.*error:)' || true
APP_SRC="$WORK/AWGConnect.xcarchive/Products/Applications/$APP_NAME.app"
[[ -d "$APP_SRC" ]] || { echo "error: archive did not produce $APP_NAME.app" >&2; exit 1; }

APP="$WORK/stage/$APP_NAME.app"
mkdir -p "$WORK/stage"
cp -R "$APP_SRC" "$APP"
APPEX="$APP/Contents/PlugIns/AmneziaTunnelMac.appex"

echo "==> Setting version $VERSION ($BUILD_NUMBER)"
for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$plist"
done

# Signed entitlements = the target's entitlements file + the identifiers Xcode adds,
# which the provisioning profile must allow.
entitlements() { # source file, bundle id, output
    cp "$1" "$3"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$2" "$3"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$3"
}
entitlements "$ROOT/AmneziaTunnel/AmneziaTunnelMac.entitlements" com.oktayibis.awgconnect.mac.tunnel "$WORK/tunnel.entitlements"
entitlements "$ROOT/AmneziaMac/AmneziaMac.entitlements" com.oktayibis.awgconnect.mac "$WORK/app.entitlements"

SIGN=(codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"})

echo "==> Signing"
# Inside out: nested frameworks, then the extension, then the app.
while IFS= read -r -d '' framework; do
    "${SIGN[@]}" "$framework"
done < <(find "$APP" -name '*.framework' -type d -print0)
cp "$TUNNEL_PROFILE" "$APPEX/Contents/embedded.provisionprofile"
"${SIGN[@]}" --entitlements "$WORK/tunnel.entitlements" "$APPEX"
cp "$APP_PROFILE" "$APP/Contents/embedded.provisionprofile"
"${SIGN[@]}" --entitlements "$WORK/app.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging $DMG"
mkdir -p "$OUTPUT_DIR"
ln -s /Applications "$WORK/stage/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$WORK/stage" -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$DMG"

if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --wait \
        --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    xcrun stapler staple "$DMG"
fi

echo "Done: $DMG"
