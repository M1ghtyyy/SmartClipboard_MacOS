# Shared settings and helpers for the SmartClipBoard scripts. Sourced, not run directly.

APP_NAME="SmartClipBoard"
LABEL="com.vladimirbelaev.smartclipboard"   # must match CFBundleIdentifier in Resources/Info.plist
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
AGENT_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
TEMP_MEDIA_DIR="$(getconf DARWIN_USER_TEMP_DIR)$APP_NAME"

# Stops SmartClipBoard whether it was started at login (launchd) or opened by hand.
stop_app() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    for _ in $(seq 1 25); do
        launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -x "$APP_NAME" 2>/dev/null || true
    for _ in $(seq 1 25); do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.2
    done
}

# Writes the per-user LaunchAgent that starts the app at login and after a crash.
write_agent_plist() {
    mkdir -p "$(dirname "$AGENT_PLIST")"
    cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP_PATH/Contents/MacOS/$APP_NAME</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<!-- Restart after a crash, but stay quit when you choose Quit. -->
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF
}

# Turns auto-start on: writes the LaunchAgent and starts the app through launchd right away.
enable_autostart() {
    write_agent_plist
    launchctl bootstrap "$DOMAIN" "$AGENT_PLIST"
}
