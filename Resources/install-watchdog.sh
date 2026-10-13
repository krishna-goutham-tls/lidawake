#!/bin/sh
# LidAwake: install and load the watchdog LaunchAgent. Runs as the user.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

LABEL=space.thelaunch.lidawake.watchdog
SRC_DIR=$(cd "$(dirname "$0")" && pwd)

# --- Test hooks (not used in production) ---------------------------------
# LIDAWAKE_DRY_RUN=1   write files under LIDAWAKE_HOME but print launchctl
#                      commands instead of running them. Requires LIDAWAKE_HOME.
# LIDAWAKE_HOME        replaces $HOME.
DRY_RUN=${LIDAWAKE_DRY_RUN:-0}
if [ "$DRY_RUN" = 1 ]; then
    [ -n "${LIDAWAKE_HOME:-}" ] || { echo "LidAwake watchdog: dry run needs LIDAWAKE_HOME" >&2; exit 1; }
fi
HOME_DIR=${LIDAWAKE_HOME:-$HOME}
# -------------------------------------------------------------------------

SUPPORT_DIR="$HOME_DIR/Library/Application Support/LidAwake"
WATCHDOG="$SUPPORT_DIR/watchdog.sh"
AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
PLIST="$AGENTS_DIR/$LABEL.plist"
LOG="$HOME_DIR/Library/Logs/LidAwake.log"
DOMAIN="gui/$(id -u)"

log() {
    mkdir -p "$HOME_DIR/Library/Logs" &&
        printf '%s [setup] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*" >>"$LOG" || true
}

fail() {
    printf 'LidAwake watchdog install failed: %s\n' "$*" >&2
    log "watchdog install failed: $*"
    exit 1
}

run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf 'DRY RUN: %s\n' "$*"
    else
        "$@"
    fi
}

xml_escape() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

[ -f "$SRC_DIR/watchdog.sh" ] || fail "watchdog.sh not found next to this script"

mkdir -p "$SUPPORT_DIR" "$AGENTS_DIR" || fail "could not create folders"

tmp_wd="$WATCHDOG.tmp.$$"
cp "$SRC_DIR/watchdog.sh" "$tmp_wd" && chmod 755 "$tmp_wd" && mv -f "$tmp_wd" "$WATCHDOG" ||
    { rm -f "$tmp_wd"; fail "could not copy watchdog.sh"; }

tmp_plist="$PLIST.tmp.$$"
cat >"$tmp_plist" <<EOF || { rm -f "$tmp_plist"; fail "could not write plist"; }
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>$(xml_escape "$WATCHDOG")</string>
	</array>
	<key>StartInterval</key>
	<integer>60</integer>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardOutPath</key>
	<string>/dev/null</string>
	<key>StandardErrorPath</key>
	<string>/dev/null</string>
</dict>
</plist>
EOF

plutil -lint -s "$tmp_plist" >/dev/null 2>&1 || { rm -f "$tmp_plist"; fail "generated plist did not pass plutil -lint"; }
mv -f "$tmp_plist" "$PLIST" || { rm -f "$tmp_plist"; fail "could not install plist"; }

run launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

# bootstrap can briefly fail with an I/O error right after a bootout.
loaded=0
for _ in 1 2 3; do
    if run launchctl bootstrap "$DOMAIN" "$PLIST"; then
        loaded=1
        break
    fi
    sleep 1
done
[ "$loaded" = 1 ] || fail "launchctl bootstrap $DOMAIN failed"

log "watchdog installed and loaded"
echo "LidAwake: watchdog installed and loaded."
