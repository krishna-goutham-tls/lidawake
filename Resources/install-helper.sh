#!/bin/sh
# LidAwake: install the sudoers rule that lets one user run exactly
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# without a password. Runs as root (the app calls it through AppleScript
# "with administrator privileges"). Arg 1: the username to allow.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
LC_ALL=C
export PATH LC_ALL

TARGET=/etc/sudoers.d/lidawake

# --- Test hooks (not used in production) ---------------------------------
# LIDAWAKE_DRY_RUN=1   skip the root check; print privileged commands instead
#                      of running them. Requires LIDAWAKE_HOME.
# LIDAWAKE_HOME        stands in for the user's home folder (log location).
# LIDAWAKE_SUDOERS_PATH  in dry run, the validated rule is copied here.
DRY_RUN=${LIDAWAKE_DRY_RUN:-0}
# -------------------------------------------------------------------------

fail() {
    printf 'LidAwake setup failed: %s\n' "$*" >&2
    log "setup failed: $*"
    exit 1
}

USER_NAME=""
USER_HOME=""

# Writes as the user, so the log never ends up root-owned and a symlink
# planted at the log path cannot make root write somewhere else.
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

if [ "$DRY_RUN" = 1 ]; then
    [ -n "${LIDAWAKE_HOME:-}" ] || { echo "LidAwake setup: dry run needs LIDAWAKE_HOME" >&2; exit 1; }
elif [ "$(id -u)" -ne 0 ]; then
    echo "LidAwake setup failed: must run as root" >&2
    exit 1
fi

[ $# -eq 1 ] || { echo "usage: install-helper.sh <username>" >&2; exit 1; }
USER_NAME=$1
case $USER_NAME in
    '' | [!a-z_]* | *[!a-z0-9_.-]*)
        echo "LidAwake setup failed: invalid username" >&2
        exit 1 ;;
esac
id -u "$USER_NAME" >/dev/null 2>&1 || { echo "LidAwake setup failed: no such user: $USER_NAME" >&2; exit 1; }

if [ "$DRY_RUN" = 1 ]; then
    USER_HOME=$LIDAWAKE_HOME
else
    USER_HOME=$(dscl . -read "/Users/$USER_NAME" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')
fi

if [ -r /etc/sudoers ]; then
    if ! grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers\.d/?[[:space:]]*$' /etc/sudoers; then
        printf 'LidAwake setup warning: /etc/sudoers does not include /etc/sudoers.d; the rule will have no effect\n' >&2
        log "warning: /etc/sudoers does not include /etc/sudoers.d"
    fi
fi

TMP=$(mktemp /tmp/lidawake-sudoers.XXXXXX) || fail "could not create temp file"
trap 'rm -f "$TMP"' EXIT INT TERM

cat >"$TMP" <<EOF
# LidAwake: lets $USER_NAME turn lid-close sleep off and on without a password.
# Allows only the two pmset commands below, nothing else.
# Remove with LidAwake's "Remove closed-lid permission", or run:
#   sudo rm /etc/sudoers.d/lidawake && sudo pmset -a disablesleep 0
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF

/usr/sbin/visudo -cf "$TMP" >/dev/null 2>&1 || fail "generated sudoers rule did not pass visudo"

if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY RUN: install -d -m 0755 -o root -g wheel /etc/sudoers.d\n'
    printf 'DRY RUN: install -m 0440 -o root -g wheel %s %s\n' "$TMP" "$TARGET"
    if [ -n "${LIDAWAKE_SUDOERS_PATH:-}" ]; then
        cp "$TMP" "$LIDAWAKE_SUDOERS_PATH"
    fi
else
    [ -d /etc/sudoers.d ] || install -d -m 0755 -o root -g wheel /etc/sudoers.d || fail "could not create /etc/sudoers.d"
    install -m 0440 -o root -g wheel "$TMP" "$TARGET" || fail "could not install $TARGET"
    # Never leave a file behind that breaks sudo for the whole machine.
    if ! /usr/sbin/visudo -c >/dev/null 2>&1; then
        rm -f "$TARGET"
        fail "sudo configuration did not validate after install; rule removed"
    fi
fi

log "closed-lid permission installed for $USER_NAME"
echo "LidAwake: closed-lid permission installed for $USER_NAME."
