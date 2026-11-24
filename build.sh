#!/bin/bash
# Builds the development app, or an isolated local app with --custom.
set -euo pipefail
cd "$(dirname "$0")"

CUSTOM=false
NAME="Mac TV"
case "$#:${1:-}" in
    0:) ;;
    1:--custom) CUSTOM=true; NAME="MacTV Custom" ;;
    *) echo "Usage: $0 [--custom]" >&2; exit 2 ;;
esac

# One universal binary: Apple silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
BUILD_LOCATION=(--scratch-path "${MACTV_BUILD_DIR:-.build}")
swift build -c release "${ARCHS[@]}" "${BUILD_LOCATION[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" "${BUILD_LOCATION[@]}" --show-bin-path)"

DESTINATION="$(pwd)/build/$NAME.app"
mkdir -p build
STAGING="$(mktemp -d "$(pwd)/build/.mactv-build.XXXXXXXX")"
LOCK="$DESTINATION.lock"
LOCKED=false
cleanup() {
    if [[ -e "$STAGING/previous.app" && ! -e "$DESTINATION" ]]; then
        if ! mv "$STAGING/previous.app" "$DESTINATION"; then
            echo "Previous app remains at $STAGING/previous.app" >&2
            if $LOCKED; then rmdir "$LOCK"; fi
            return 1
        fi
    fi
    if $LOCKED; then rmdir "$LOCK"; fi
    rm -rf "$STAGING"
}
trap cleanup EXIT

APP="$STAGING/$NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MacTV" "$APP/Contents/MacOS/MacTV"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Icons "$APP/Contents/Resources/Icons"
cp Assets/AppIcon.icns Assets/AppIcon.png "$APP/Contents/Resources/"
# Swift packages' resource bundles (TelemetryDeck's privacy manifest).
for bundle in "$BIN"/*.bundle; do [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"; done

DEFAULT_IDENTITY="Mac TV Local Signing"
if $CUSTOM; then
    VERSION=$(cat VERSION)
    if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "VERSION must be MAJOR.MINOR.PATCH" >&2
        exit 2
    fi
    BUILD_VERSION="$(( ${VERSION%%.*} + 1 )).${VERSION#*.}"
    PLIST="$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.couch.tv.custom' \
        -c "Set :CFBundleDisplayName $NAME" -c "Set :CFBundleName $NAME" \
        -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_VERSION" \
        -c 'Set :NSLocalNetworkUsageDescription 같은 Wi-Fi에서 아이폰을 MacTV 리모컨으로 연결하려면 로컬 네트워크 접근이 필요합니다.' \
        -c 'Delete :TelemetryDeckAppID' "$PLIST"
    mkdir -p "$APP/Contents/Resources/Licenses"
    cp LICENSE "$APP/Contents/Resources/Licenses/MacTV.txt"
    cp Packages/TelemetryDeck/LICENSE "$APP/Contents/Resources/Licenses/TelemetryDeck.txt"
    DEFAULT_IDENTITY="MacTV Custom Local Signing"
fi
# Sign with the local certificate when it exists (scripts/make-signing-cert.sh), so macOS keeps
# permissions like Accessibility across builds; otherwise sign ad hoc.
IDENTITY="${MACTV_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if security find-identity -p codesigning 2>/dev/null | grep -F "\"$IDENTITY\"" >/dev/null; then
    codesign --force --entitlements Assets/MacTV.entitlements --sign "$IDENTITY" "$APP" >/dev/null
else
    codesign --force --entitlements Assets/MacTV.entitlements --sign - "$APP" >/dev/null
fi
codesign --verify --deep --strict "$APP"

# Replace only a complete, verified workspace bundle, keeping the previous one if publication fails.
if ! mkdir "$LOCK"; then echo "Another build is publishing $DESTINATION" >&2; exit 1; fi
LOCKED=true
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGING/previous.app"; fi
mv "$APP" "$DESTINATION"

echo "Built $DESTINATION"
