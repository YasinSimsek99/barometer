#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version-tag> <notarized-app-zip>" >&2
  exit 64
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$1"
ARCHIVE="$2"
IDENTITY="$PROJECT_DIR/Sources/BarometerCore/Resources/AppIdentity.json"
REPOSITORY="$(/usr/bin/plutil -extract repository raw -- "$IDENTITY")"
APP_NAME="$(/usr/bin/plutil -extract appName raw -- "$IDENTITY")"
BUNDLE_ID="$(/usr/bin/plutil -extract bundleIdentifier raw -- "$IDENTITY")"
EXECUTABLE_NAME="$(/usr/bin/plutil -extract executableName raw -- "$IDENTITY")"
BRIDGE_NAME="$(/usr/bin/plutil -extract bridgeExecutableName raw -- "$IDENTITY")"
FORMULA_NAME="$(echo "$APP_NAME" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr -cd '[:alnum:]')"
BINARY_SHA256="$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')"
OUTPUT_DIR="$PROJECT_DIR/.build/release-assets"

/bin/mkdir -p "$OUTPUT_DIR"
/usr/bin/sed \
  -e "s|@VERSION@|$VERSION|g" \
  -e "s|@BINARY_SHA256@|$BINARY_SHA256|g" \
  -e "s|@REPOSITORY@|$REPOSITORY|g" \
  -e "s|@APP_NAME@|$APP_NAME|g" \
  "$PROJECT_DIR/scripts/install-release.sh.in" > "$OUTPUT_DIR/install-$VERSION.sh"
/bin/chmod 755 "$OUTPUT_DIR/install-$VERSION.sh"

/usr/bin/sed \
  -e "s|@VERSION@|${VERSION#v}|g" \
  -e "s|@TAG@|$VERSION|g" \
  -e "s|@BINARY_SHA256@|$BINARY_SHA256|g" \
  -e "s|@REPOSITORY@|$REPOSITORY|g" \
  -e "s|@APP_NAME@|$APP_NAME|g" \
  -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" \
  -e "s|@EXECUTABLE_NAME@|$EXECUTABLE_NAME|g" \
  -e "s|@BRIDGE_NAME@|$BRIDGE_NAME|g" \
  -e "s|@FORMULA_NAME@|$FORMULA_NAME|g" \
  "$PROJECT_DIR/Packaging/homebrew/barometer.rb.in" > "$OUTPUT_DIR/$FORMULA_NAME.rb"

echo "$OUTPUT_DIR"
