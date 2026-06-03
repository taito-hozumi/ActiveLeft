#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP_DIR="$ROOT_DIR/build/ActiveLeft.app"
SOURCE_APP_BINARY="$SOURCE_APP_DIR/Contents/MacOS/ActiveLeft"
INSTALL_DIR="${ACTIVELEFT_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_DIR="$INSTALL_DIR/ActiveLeft.app"
APP_BINARY="$INSTALLED_APP_DIR/Contents/MacOS/ActiveLeft"
LABEL="${ACTIVELEFT_LAUNCH_AGENT_LABEL:-com.hozumitaito.activeleft}"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
SERVICE_NAME="gui/$(id -u)/$LABEL"

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

stop_running_activeleft() {
  pkill -TERM -x ActiveLeft >/dev/null 2>&1 || return 0

  for _ in {1..20}; do
    if ! pgrep -x ActiveLeft >/dev/null 2>&1; then
      return 0
    fi

    sleep 0.1
  done

  pkill -KILL -x ActiveLeft >/dev/null 2>&1 || true
}

if [[ ! -x "$SOURCE_APP_BINARY" ]]; then
  "$ROOT_DIR/scripts/build_app.sh" release
fi

mkdir -p "$INSTALL_DIR" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
stop_running_activeleft

rm -rf "$INSTALLED_APP_DIR"
cp -R "$SOURCE_APP_DIR" "$INSTALLED_APP_DIR"

PLIST_LABEL="$(printf '%s' "$LABEL" | xml_escape)"
PLIST_APP_BINARY="$(printf '%s' "$APP_BINARY" | xml_escape)"
PLIST_STDOUT="$(printf '%s' "$LOG_DIR/ActiveLeft.log" | xml_escape)"
PLIST_STDERR="$(printf '%s' "$LOG_DIR/ActiveLeft.error.log" | xml_escape)"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PLIST_APP_BINARY</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$PLIST_STDOUT</string>
  <key>StandardErrorPath</key>
  <string>$PLIST_STDERR</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST_PATH"
plutil -lint "$PLIST_PATH" >/dev/null

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "$SERVICE_NAME"
launchctl kickstart -k "$SERVICE_NAME"

echo "Installed and started $LABEL"
echo "$INSTALLED_APP_DIR"
echo "$PLIST_PATH"
