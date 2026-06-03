#!/usr/bin/env bash
set -euo pipefail

LABEL="${ACTIVELEFT_LAUNCH_AGENT_LABEL:-com.hozumitaito.activeleft}"
INSTALL_DIR="${ACTIVELEFT_INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP_DIR="$INSTALL_DIR/ActiveLeft.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
pkill -TERM -x ActiveLeft >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -rf "$INSTALLED_APP_DIR"

echo "Uninstalled $LABEL"
