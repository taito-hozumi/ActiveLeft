#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
BUNDLE_ID="${ACTIVELEFT_BUNDLE_ID:-com.hozumitaito.activeleft}"
VERSION="${ACTIVELEFT_VERSION:-0.1.0}"
BUILD_NUMBER="${ACTIVELEFT_BUILD_NUMBER:-1}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 2
fi

cd "$ROOT_DIR"

mkdir -p "$ROOT_DIR/build"

APP_DIR="$ROOT_DIR/build/ActiveLeft.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SWIFT_BUILD_LOG="$ROOT_DIR/build/swift-build.log"
BINARY_PATH="$ROOT_DIR/.build/$CONFIGURATION/ActiveLeft"
BUILD_ENGINE="swift"

if ! swift build -c "$CONFIGURATION" > "$SWIFT_BUILD_LOG" 2>&1; then
  echo "swift build failed in this Command Line Tools environment; using clang fallback." >&2
  echo "SwiftPM log: $SWIFT_BUILD_LOG" >&2
  make activeleft-bin
  BINARY_PATH="$ROOT_DIR/build/ActiveLeft"
  BUILD_ENGINE="clang"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/ActiveLeft"
chmod 755 "$MACOS_DIR/ActiveLeft"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>ActiveLeft</string>
  <key>CFBundleExecutable</key>
  <string>ActiveLeft</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ActiveLeft</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR using $BUILD_ENGINE"
echo "Bundle identifier: $BUNDLE_ID"
