#!/bin/bash
# Stops SmartClipBoard and removes the app, its login item and its temporary files.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

stop_app
rm -f "$AGENT_PLIST"
rm -rf "$APP_PATH" "$TEMP_MEDIA_DIR"

echo "$APP_NAME is uninstalled. You can delete this folder now."
