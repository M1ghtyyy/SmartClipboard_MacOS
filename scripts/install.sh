#!/bin/bash
# Builds SmartClipBoard from source, installs it to ~/Applications and starts it.
#   --autostart      start at every login (the default for a first install)
#   --no-autostart   don't start at login
#   --clean          rebuild everything from scratch
# Run it again to update; without --autostart/--no-autostart the current setting is kept.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

autostart=""
clean=""
for arg in "$@"; do
    case "$arg" in
        --autostart) autostart="on" ;;
        --no-autostart) autostart="off" ;;
        --clean) clean="--clean" ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see scripts/install.sh --help)"; exit 1 ;;
    esac
done

if [ -z "$autostart" ]; then
    # Updating an install whose auto-start was turned off: keep it off.
    if [ -d "$APP_PATH" ] && [ ! -f "$AGENT_PLIST" ]; then autostart="off"; else autostart="on"; fi
fi

scripts/build.sh $clean

stop_app
mkdir -p "$INSTALL_DIR"
rm -rf "$APP_PATH"
cp -R "build/$APP_NAME.app" "$APP_PATH"

if [ "$autostart" = "on" ]; then
    enable_autostart
else
    rm -f "$AGENT_PLIST"
    open "$APP_PATH"
fi

echo
echo "$APP_NAME is installed in $APP_PATH and running."
echo "Auto-start at login: $autostart   (change it with scripts/autostart.sh on|off)"
echo "Move your pointer to the notch to open it."
