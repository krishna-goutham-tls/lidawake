#!/bin/sh
# LidAwake: unload and remove the watchdog LaunchAgent. Runs as the user.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

LABEL=space.thelaunch.lidawake.watchdog

# --- Test hooks (not used in production) ---------------------------------
# LIDAWAKE_DRY_RUN=1   remove files under LIDAWAKE_HOME but print launchctl
#                      commands instead of running them. Requires LIDAWAKE_HOME.
# LIDAWAKE_HOME        replaces $HOME.
DRY_RUN=${LIDAWAKE_DRY_RUN:-0}
if [ "$DRY_RUN" = 1 ]; then
    [ -n "${LIDAWAKE_HOME:-}" ] || { echo "LidAwake watchdog: dry run needs LIDAWAKE_HOME" >&2; exit 1; }
fi
HOME_DIR=${LIDAWAKE_HOME:-$HOME}
# -------------------------------------------------------------------------

WATCHDOG="$HOME_DIR/Library/Application Support/LidAwake/watchdog.sh"
PLIST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME_DIR/Library/Logs/LidAwake.log"

log() {
    mkdir -p "$HOME_DIR/Library/Logs" &&
        printf '%s [setup] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*" >>"$LOG" || true
}

if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY RUN: launchctl bootout gui/%s/%s\n' "$(id -u)" "$LABEL"
else
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
fi

if ! rm -f "$PLIST" "$WATCHDOG"; then
    echo "LidAwake watchdog removal failed: could not delete files" >&2
    log "watchdog removal failed: could not delete files"
    exit 1
fi

log "watchdog removed"
echo "LidAwake: watchdog removed."
