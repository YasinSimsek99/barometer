#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="$PROJECT_DIR/Sources/BarometerCore/Resources/AppIdentity.json"
OUTPUT_ROOT="${1:-$PROJECT_DIR/.build}"
VERSION="${BAROMETER_VERSION:-0.1.0-dev}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_NAME="$(/usr/bin/plutil -extract appName raw -- "$IDENTITY")"
BUNDLE_ID="$(/usr/bin/plutil -extract bundleIdentifier raw -- "$IDENTITY")"
EXECUTABLE_NAME="$(/usr/bin/plutil -extract executableName raw -- "$IDENTITY")"
BRIDGE_NAME="$(/usr/bin/plutil -extract bridgeExecutableName raw -- "$IDENTITY")"
APP_BUNDLE="$OUTPUT_ROOT/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

cd "$PROJECT_DIR"
/usr/bin/swift build -c release --product BarometerApp
/usr/bin/swift build -c release --product barometer-bridge
BIN_DIR="$(/usr/bin/swift build -c release --show-bin-path)"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Helpers" "$CONTENTS/Resources"
/bin/cp "$BIN_DIR/BarometerApp" "$CONTENTS/MacOS/$EXECUTABLE_NAME"
/bin/cp "$BIN_DIR/barometer-bridge" "$CONTENTS/Helpers/$BRIDGE_NAME"
RESOURCE_BUNDLE="$(/usr/bin/find "$BIN_DIR" -maxdepth 1 -type d -name '*BarometerCore.bundle' -print -quit)"
[[ -n "$RESOURCE_BUNDLE" ]] || { echo "BarometerCore resource bundle is missing." >&2; exit 1; }
/bin/cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
/bin/cp "$PROJECT_DIR/Sources/BarometerCore/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

PLIST="$CONTENTS/Info.plist"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "$EXECUTABLE_NAME" "$PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string AppIcon "$PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$PLIST"
/usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$PLIST"
/usr/bin/plutil -insert CFBundleSignature -string '????' "$PLIST"
/usr/bin/plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "${BAROMETER_BUILD_NUMBER:-1}" "$PLIST"
/usr/bin/plutil -insert CFBundleSupportedPlatforms -array "$PLIST"
/usr/bin/plutil -insert CFBundleSupportedPlatforms.0 -string MacOSX "$PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string 14.0 "$PLIST"
/usr/bin/plutil -insert LSUIElement -bool YES "$PLIST"
/usr/bin/plutil -insert LSMultipleInstancesProhibited -bool YES "$PLIST"
/usr/bin/plutil -insert NSPrincipalClass -string NSApplication "$PLIST"
/usr/bin/plutil -insert NSHumanReadableCopyright -string "Copyright © 2026 Yasin Simsek and contributors" "$PLIST"
/usr/bin/printf 'APPL????' > "$CONTENTS/PkgInfo"

/bin/chmod 755 "$CONTENTS/MacOS/$EXECUTABLE_NAME" "$CONTENTS/Helpers/$BRIDGE_NAME"
/usr/bin/codesign --force --sign - --options runtime "$CONTENTS/Helpers/$BRIDGE_NAME"
/usr/bin/codesign --force --sign - --options runtime --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
