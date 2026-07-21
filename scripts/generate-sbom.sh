#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <version> <output-file>" >&2
  exit 64
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="$PROJECT_DIR/Sources/BarometerCore/Resources/AppIdentity.json"
NAME="$(/usr/bin/plutil -extract appName raw -- "$IDENTITY")"
BUNDLE_ID="$(/usr/bin/plutil -extract bundleIdentifier raw -- "$IDENTITY")"
VERSION="$1"
OUTPUT="$2"
SERIAL="urn:uuid:$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"

/bin/mkdir -p "$(/usr/bin/dirname "$OUTPUT")"
/bin/cat > "$OUTPUT" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "$SERIAL",
  "version": 1,
  "metadata": {
    "timestamp": "$TIMESTAMP",
    "component": {
      "type": "application",
      "name": "$NAME",
      "version": "$VERSION",
      "bom-ref": "$BUNDLE_ID@$VERSION",
      "licenses": [{"license": {"id": "MIT"}}]
    }
  },
  "components": []
}
EOF
