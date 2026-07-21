#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="$PROJECT_DIR/Sources/BarometerCore/Resources/AppIdentity.json"
APP_NAME="$(/usr/bin/plutil -extract appName raw -- "$IDENTITY")"
EXECUTABLE_NAME="$(/usr/bin/plutil -extract executableName raw -- "$IDENTITY")"
INSTALL_DIR="${BAROMETER_INSTALL_DIR:-$HOME/Applications}"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "$APP_NAME is not installed at $APP_PATH"
  exit 0
fi

if [[ -x "$EXECUTABLE" ]]; then
  "$EXECUTABLE" --prepare-uninstall
fi

TRASH_DESTINATION="$HOME/.Trash/$APP_NAME-$(/bin/date +%Y%m%d-%H%M%S).app"
/bin/mv "$APP_PATH" "$TRASH_DESTINATION"
echo "$APP_NAME was disconnected and moved to $TRASH_DESTINATION"
