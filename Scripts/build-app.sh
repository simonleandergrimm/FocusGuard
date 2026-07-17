#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/FocusGuard.app"
SCRATCH_DIR="$ROOT_DIR/.build"

export CLANG_MODULE_CACHE_PATH="$SCRATCH_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$SCRATCH_DIR/ModuleCache"
export XDG_CACHE_HOME="$SCRATCH_DIR/Cache"

swift build --package-path "$ROOT_DIR" -c release --disable-sandbox --scratch-path "$SCRATCH_DIR"
BIN_DIR=$(swift build --package-path "$ROOT_DIR" -c release --disable-sandbox --scratch-path "$SCRATCH_DIR" --show-bin-path)

if [ -d "$APP_DIR" ]; then
    /bin/rm -rf "$APP_DIR"
fi

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources"
/bin/cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$BIN_DIR/FocusGuardApp" "$APP_DIR/Contents/MacOS/FocusGuardApp"
/bin/cp "$BIN_DIR/FocusGuardHelper" "$APP_DIR/Contents/Helpers/FocusGuardHelper"
/bin/cp -R "$ROOT_DIR/BrowserExtension" "$APP_DIR/Contents/Resources/BrowserExtension"
/bin/cp "$ROOT_DIR/Resources/FocusGuard.icns" "$APP_DIR/Contents/Resources/FocusGuardBlue.icns"
/bin/chmod 755 "$APP_DIR/Contents/MacOS/FocusGuardApp" "$APP_DIR/Contents/Helpers/FocusGuardHelper"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/plutil -lint "$APP_DIR/Contents/Info.plist"

echo "$APP_DIR"
