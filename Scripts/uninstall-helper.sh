#!/bin/sh
set -eu

LABEL="com.local.FocusGuard.helper"
HELPER="/Library/PrivilegedHelperTools/FocusGuardHelper"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this maintenance script with sudo."
    exit 1
fi

if [ -x "$HELPER" ]; then
    "$HELPER" --clear-hosts
fi

if /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$LABEL"
fi

/bin/rm -f "$HELPER" "$PLIST"
echo "FocusGuard helper removed."
