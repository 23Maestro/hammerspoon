#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="XSpoon"
BUNDLE_ID="com.singleton23.XSpoon"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_BUNDLE="/Applications/$APP_NAME.app"
LEGACY_INSTALL_BUNDLE="/Applications/XSpoonMenu.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/XSpoonMenu.icns"
SIGNING_IDENTITY="${XSPOON_SIGNING_IDENTITY:-Apple Development: jay23singleton@gmail.com (U7MJ89XZ2M)}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "XSpoonMenu" >/dev/null 2>&1 || true
rm -rf "$DIST_DIR"
rm -rf "$LEGACY_INSTALL_BUNDLE"
mkdir -p "$DIST_DIR"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/XSpoonMenu"
RESOURCE_BUNDLE="$(swift build --show-bin-path)/XSpoonMenu_XSpoonMenu.bundle"

mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>XSpoonMenu.icns</string>
<key>CFBundleIconName</key><string>XSpoonMenu</string>
<key>CFBundleIconFiles</key><array><string>XSpoonMenu.icns</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

cp "$ICON_SOURCE" "$APP_RESOURCES/XSpoonMenu.icns"

# Accessibility permissions survive rebuilds only when the app keeps a stable signing identity.
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$INSTALL_BUNDLE"
ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"

touch "$INSTALL_BUNDLE"
"/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister" -f "$INSTALL_BUNDLE" >/dev/null 2>&1 || true

case "$MODE" in
  run) /usr/bin/open -n "$INSTALL_BUNDLE" ;;
  --verify|verify) /usr/bin/open -n "$INSTALL_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  --logs|logs) /usr/bin/open -n "$INSTALL_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) /usr/bin/open -n "$INSTALL_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  *) echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
