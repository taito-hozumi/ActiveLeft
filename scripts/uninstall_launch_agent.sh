#!/usr/bin/env bash
set -euo pipefail

LABEL="${ACTIVELEFT_LAUNCH_AGENT_LABEL:-com.hozumitaito.activeleft}"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "Uninstalled $LABEL"
