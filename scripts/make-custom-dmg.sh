#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${MACTV_SKIP_BUILD:-0}" != 1 ]]; then ./build.sh --release; fi
APP="build/MacTV Custom.app"
VERSION=$(cat VERSION)
PLIST="$APP/Contents/Info.plist"
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]]
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" != local.couch.tv.custom ||
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")" != CouchDial ||
      -e "$APP/Contents/Resources/Icons" ]]; then
    echo "Only the public CouchDial app can be packaged." >&2
    exit 1
fi
codesign --verify --deep --strict "$APP"

NAME="CouchDial-$VERSION.dmg"
STAGING=$(mktemp -d "build/.custom-dmg.XXXXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/content"
ditto "$APP" "$STAGING/content/MacTV Custom.app"
ln -s /Applications "$STAGING/content/Applications"
hdiutil create -volname "CouchDial" -srcfolder "$STAGING/content" -format UDZO "$STAGING/$NAME"
hdiutil verify "$STAGING/$NAME"
(cd "$STAGING" && shasum -a 256 "$NAME" > "$NAME.sha256")
mv -f "$STAGING/$NAME" "build/$NAME"
mv -f "$STAGING/$NAME.sha256" "build/$NAME.sha256"
echo "Built $(pwd)/build/$NAME"
