#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="$PROJECT_DIR/Sources/BarometerCore/Resources/AppIdentity.json"
APP_NAME="$(/usr/bin/plutil -extract appName raw -- "$IDENTITY")"
INSTALL_DIR="${BAROMETER_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_DIR/$APP_NAME.app"

if [[ "$EUID" -eq 0 ]]; then
  echo "Do not run this installer with sudo. Barometer is installed only for the current user." >&2
  exit 1
fi

STAGING="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/barometer-install.XXXXXX")"
cleanup() { /bin/rm -rf "$STAGING"; }
trap cleanup EXIT

if ! /usr/bin/xcrun --find swift >/dev/null 2>&1; then
  echo "Swift is missing. Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

/bin/mkdir -p "$INSTALL_DIR"
if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "$INSTALL_DIR is not writable by $USER. Do not use sudo; repair the directory ownership first." >&2
  exit 1
fi
"$PROJECT_DIR/scripts/build-app.sh" "$STAGING"

# This backup/atomic-swap pattern intentionally mirrors scripts/install-release.sh.in — keep them in sync.
BACKUP=""
if [[ -e "$DESTINATION" ]]; then
  BACKUP="$STAGING/$APP_NAME.previous.app"
  /bin/mv "$DESTINATION" "$BACKUP"
fi

if /bin/mv "$STAGING/$APP_NAME.app" "$DESTINATION"; then
  /usr/bin/codesign --verify --deep --strict "$DESTINATION"
  echo "$APP_NAME installed at $DESTINATION"
else
  [[ -n "$BACKUP" && -e "$BACKUP" ]] && /bin/mv "$BACKUP" "$DESTINATION"
  echo "Installation failed; the previous version was restored." >&2
  exit 1
fi
