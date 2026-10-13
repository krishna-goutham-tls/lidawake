#!/bin/sh
# LidAwake watchdog. Run by launchd every 60 s and at login, as the user.
# If the app left lid-close sleep disabled and is no longer running, turn
# normal sleep back on. Silent when there is nothing to do.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

# --- Test hooks (not used in production) ---------------------------------
# LIDAWAKE_DRY_RUN=1        print the pmset command instead of running it.
#                           Requires LIDAWAKE_HOME.
# LIDAWAKE_HOME             replaces $HOME.
# LIDAWAKE_PROCESS_NAME     process to look for instead of LidAwake.
DRY_RUN=${LIDAWAKE_DRY_RUN:-0}
if [ "$DRY_RUN" = 1 ]; then
    [ -n "${LIDAWAKE_HOME:-}" ] || { echo "LidAwake watchdog: dry run needs LIDAWAKE_HOME" >&2; exit 1; }
fi
HOME_DIR=${LIDAWAKE_HOME:-$HOME}
PROCESS_NAME=${LIDAWAKE_PROCESS_NAME:-LidAwake}
# -------------------------------------------------------------------------

SUPPORT_DIR="$HOME_DIR/Library/Application Support/LidAwake"
MARKER="$SUPPORT_DIR/lid-session-active"
LOCK="$SUPPORT_DIR/.watchdog.lock"
LOG="$HOME_DIR/Library/Logs/LidAwake.log"

[ -e "$MARKER" ] || exit 0
pgrep -x -u "$(id -u)" "$PROCESS_NAME" >/dev/null 2>&1 && exit 0

log() {
    mkdir -p "$HOME_DIR/Library/Logs" &&
        printf '%s [watchdog] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*" >>"$LOG" || true
}

# A lock left by a killed run must not block the watchdog forever.
if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null || true
fi
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

# Another run may have finished between the first check and taking the lock.
[ -e "$MARKER" ] || exit 0

if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY RUN: /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0\n'
    ok=1
elif err=$(/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 2>&1); then
    ok=1
else
    ok=0
fi

if [ "$ok" = 1 ]; then
    rm -f "$MARKER"
    log "app not running, restored normal sleep"
else
    log "app not running, could not restore normal sleep: $(printf '%s' "${err:-unknown error}" | tr '\n' ' ')"
    exit 1
fi
