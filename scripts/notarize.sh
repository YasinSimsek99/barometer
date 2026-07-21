#!/bin/bash
set -euo pipefail

# Re-signs an already-built Barometer.app (see build-app.sh) with a Developer
# ID Application certificate, submits it to Apple for notarization, and
# staples the resulting ticket so Gatekeeper can verify it offline. This is
# the single notarization code path for both a maintainer's local dry run
# and CI's release job (see .github/workflows/release.yml) — credentials are
# read from environment variables so both callers can share it unchanged.
#
# One-time setup, once your Apple Developer account and certificate exist:
#   1. Keychain Access > Certificate Assistant > Request a Certificate From
#      a Certificate Authority to create a CSR, then create a
#      "Developer ID Application" certificate at
#      https://developer.apple.com/account/resources/certificates/list
#      and install it in your login keychain (double-click the download).
#   2. Create an App Store Connect API key at
#      https://appstoreconnect.apple.com/access/api (an "Individual" key
#      with the "Developer" role is sufficient), download its .p8 once, then:
#        xcrun notarytool store-credentials barometer-notary \
#          --key /path/to/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>
#
# Usage:
#   scripts/notarize.sh <path-to-Barometer.app> "<codesign-identity>"
#
# Credentials (set one of the two):
#   Local dry run:  NOTARY_PROFILE=barometer-notary
#   CI:             NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_PATH
#
# Example (local):
#   scripts/build-app.sh
#   NOTARY_PROFILE=barometer-notary \
#     scripts/notarize.sh .build/Barometer.app "Developer ID Application: Yasin Simsek (TEAMID)"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-bundle> <codesign-identity>" >&2
  exit 64
fi

APP_BUNDLE="$1"
CODESIGN_IDENTITY="$2"
ZIP_PATH="${APP_BUNDLE%.app}-notarize.zip"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_KEY_PATH:-}" ]]; then
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  echo "Set NOTARY_PROFILE (local) or NOTARY_KEY_ID/NOTARY_ISSUER_ID/NOTARY_KEY_PATH (CI)." >&2
  exit 64
fi

[[ -d "$APP_BUNDLE" ]] || { echo "$APP_BUNDLE does not exist. Run scripts/build-app.sh first." >&2; exit 1; }

cleanup() { /bin/rm -f "$ZIP_PATH"; }
trap cleanup EXIT

echo "Signing with $CODESIGN_IDENTITY (hardened runtime, secure timestamp)..."
for helper in "$APP_BUNDLE"/Contents/Helpers/*; do
  /usr/bin/codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$helper"
done
/usr/bin/codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Submitting to Apple notary service..."
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
/usr/bin/xcrun notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait

echo "Stapling notarization ticket..."
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl --assess --type execute --verbose "$APP_BUNDLE"

echo "$APP_BUNDLE is signed, notarized, and stapled."
