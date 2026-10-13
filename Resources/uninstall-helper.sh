#!/bin/sh
# LidAwake: restore normal sleep and remove the sudoers rule.
# Runs as root. Arg 1 (optional): the username, used only to find the log.
# Falls back to $SUDO_USER.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LC_ALL=C
export PATH LC_ALL

TARGET=/etc/sudoers.d/lidawake

# --- Test hooks (not used in production) ---------------------------------
# LIDAWAKE_DRY_RUN=1   skip the root check; print privileged commands instead
#                      of running them. Requires LIDAWAKE_HOME.
# LIDAWAKE_HOME        stands in for the user's home folder (log location).
DRY_RUN=${LIDAWAKE_DRY_RUN:-0}
# -------------------------------------------------------------------------

USER_NAME=""
USER_HOME=""

# Writes as the user, so the log never ends up root-owned.
log() {
    [ -n "$USER_HOME" ] || return 0
    line="$(date +%Y-%m-%dT%H:%M:%S%z) [setup] $*"
    logfile="$USER_HOME/Library/Logs/LidAwake.log"
    if [ "$DRY_RUN" = 1 ]; then
        mkdir -p "$USER_HOME/Library/Logs" && printf '%s\n' "$line" >>"$logfile"
    else
        /usr/bin/sudo -u "$USER_NAME" /bin/sh -c \
            'mkdir -p "$(dirname "$2")" && printf "%s\n" "$1" >>"$2"' \
            sh "$line" "$logfile" 2>/dev/null
    fi || true
}

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf 'DRY RUN: %s\n' "$*"
    else
        "$@"
    fi
}

if [ "$DRY_RUN" = 1 ]; then
    [ -n "${LIDAWAKE_HOME:-}" ] || { echo "LidAwake removal: dry run needs LIDAWAKE_HOME" >&2; exit 1; }
elif [ "$(id -u)" -ne 0 ]; then
    echo "LidAwake removal failed: must run as root" >&2
    exit 1
fi

USER_NAME=${1:-${SUDO_USER:-}}
case $USER_NAME in
    '' | [!a-z_]* | *[!a-z0-9_.-]*) USER_NAME="" ;;
esac
if [ -n "$USER_NAME" ] && id -u "$USER_NAME" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
        USER_HOME=$LIDAWAKE_HOME
    else
        USER_HOME=$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')
    fi
fi

status=0
if ! run /usr/bin/pmset -a disablesleep 0; then
    echo "LidAwake removal: could not run pmset -a disablesleep 0" >&2
    log "removal: pmset -a disablesleep 0 failed"
    status=1
fi

if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY RUN: rm -f %s\n' "$TARGET"
elif [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    if ! rm -f "$TARGET"; then
        echo "LidAwake removal: could not remove $TARGET" >&2
        log "removal: could not remove $TARGET"
        status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    log "closed-lid permission removed, normal sleep restored"
    echo "LidAwake: closed-lid permission removed, normal sleep restored."
fi
exit "$status"
