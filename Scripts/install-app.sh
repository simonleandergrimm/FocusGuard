#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
BUILT_APP="$ROOT_DIR/dist/FocusGuard.app"
INSTALLED_APP="/Applications/FocusGuard.app"
STAGED_APP="/Applications/.FocusGuard.installing.app"
PREVIOUS_APP="/Applications/.FocusGuard.previous.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$SCRIPT_DIR/build-app.sh"

cleanup() {
    /bin/rm -rf "$STAGED_APP"
}
trap cleanup EXIT

/bin/rm -rf "$STAGED_APP" "$PREVIOUS_APP"
/usr/bin/ditto "$BUILT_APP" "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

/usr/bin/osascript -e 'tell application id "com.local.FocusGuard" to quit' >/dev/null 2>&1 || true

if [ -d "$INSTALLED_APP" ]; then
    /bin/mv "$INSTALLED_APP" "$PREVIOUS_APP"
fi

if ! /bin/mv "$STAGED_APP" "$INSTALLED_APP"; then
    if [ -d "$PREVIOUS_APP" ]; then
        /bin/mv "$PREVIOUS_APP" "$INSTALLED_APP"
    fi
    exit 1
fi

/bin/rm -rf "$PREVIOUS_APP" "$BUILT_APP"
/usr/bin/touch "$INSTALLED_APP"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$INSTALLED_APP"
fi
if ! /usr/bin/open -a "$INSTALLED_APP"; then
    /bin/sleep 1
    /usr/bin/open -a "$INSTALLED_APP"
fi

echo "$INSTALLED_APP"
