#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/ActiveLeft.app"
APP_BINARY="$APP_DIR/Contents/MacOS/ActiveLeft"
LABEL="${ACTIVELEFT_LAUNCH_AGENT_LABEL:-com.hozumitaito.activeleft}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
SERVICE_NAME="gui/$(id -u)/$LABEL"

if [[ ! -x "$APP_BINARY" ]]; then
  "$ROOT_DIR/scripts/build_app.sh" release
fi

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$APP_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/ActiveLeft.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/ActiveLeft.error.log</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST_PATH"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "$SERVICE_NAME"
launchctl kickstart -k "$SERVICE_NAME"

echo "Installed and started $LABEL"
echo "$PLIST_PATH"
