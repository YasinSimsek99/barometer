#!/bin/bash
set -euo pipefail

# Packages a built Barometer.app into a disk image with the classic
# "drag Barometer.app onto Applications" layout. Intentionally plain: no
# custom background image or Finder-window scripting, since AppleScript
# window styling is unreliable on headless CI runners. Run this after
# scripts/notarize.sh so the .app inside is already signed, notarized, and
# stapled — the disk image itself just needs its own Developer ID signature.
#
# Usage:
#   scripts/build-dmg.sh <path-to-Barometer.app> <output.dmg> [codesign-identity]
#
# The codesign identity is optional so a local ad-hoc build can produce an
# unsigned dmg for testing the layout only; CI always passes one.

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <app-bundle> <output.dmg> [codesign-identity]" >&2
  exit 64
fi

APP_BUNDLE="$1"
OUTPUT_DMG="$2"
CODESIGN_IDENTITY="${3:-}"
APP_NAME="$(/usr/bin/basename "$APP_BUNDLE" .app)"

[[ -d "$APP_BUNDLE" ]] || { echo "$APP_BUNDLE does not exist. Run scripts/build-app.sh first." >&2; exit 1; }

STAGING="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barometer-dmg.XXXXXX")"
cleanup() { /bin/rm -rf "$STAGING"; }
trap cleanup EXIT

/bin/cp -R "$APP_BUNDLE" "$STAGING/"
/bin/ln -s /Applications "$STAGING/Applications"

/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT_DMG")"
/bin/rm -f "$OUTPUT_DMG"
/usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -ov -format UDZO "$OUTPUT_DMG"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" "$OUTPUT_DMG"
  /usr/bin/codesign --verify "$OUTPUT_DMG"
fi

echo "$OUTPUT_DMG"
