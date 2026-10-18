#!/bin/bash
# Turns starting SmartClipBoard at login on or off for the current user.
#   scripts/autostart.sh on       start at every login (restarts the app now)
#   scripts/autostart.sh off      don't start at login (the app keeps running)
#   scripts/autostart.sh status   show the current setting
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

is_running() { pgrep -x "$APP_NAME" >/dev/null; }

case "${1:-status}" in
    on)
        if [ ! -d "$APP_PATH" ]; then
            echo "$APP_NAME isn't installed yet. Run scripts/install.sh first."
            exit 1
        fi
        stop_app
        enable_autostart
        echo "Auto-start is on. $APP_NAME is running and will start at every login."
        ;;
    off)
        was_running=false
        if is_running; then was_running=true; fi
        stop_app
        rm -f "$AGENT_PLIST"
        if $was_running && [ -d "$APP_PATH" ]; then open "$APP_PATH"; fi
        echo "Auto-start is off. Start $APP_NAME yourself with:  open \"$APP_PATH\""
        ;;
    status)
        if [ -f "$AGENT_PLIST" ]; then echo "Auto-start: on"; else echo "Auto-start: off"; fi
        if is_running; then echo "$APP_NAME: running"; else echo "$APP_NAME: not running"; fi
        ;;
    *)
        echo "Usage: scripts/autostart.sh on|off|status"
        exit 1
        ;;
esac
