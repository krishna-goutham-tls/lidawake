#!/bin/sh
# Checks for the LidAwake shell scripts that need no root and change nothing
# outside a temp folder. Usage: sh scripts/selftest.sh
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
export PATH

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RES="$ROOT/Resources"
SCRIPTS="install-helper.sh uninstall-helper.sh install-watchdog.sh uninstall-watchdog.sh watchdog.sh"
LABEL=space.thelaunch.lidawake.watchdog

TMP=$(mktemp -d /tmp/lidawake-selftest.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM
FAKE_HOME="$TMP/home with space"
mkdir -p "$FAKE_HOME"
LOGFILE="$FAKE_HOME/Library/Logs/LidAwake.log"
SUPPORT="$FAKE_HOME/Library/Application Support/LidAwake"
MARKER="$SUPPORT/lid-session-active"
PLIST="$FAKE_HOME/Library/LaunchAgents/$LABEL.plist"

failures=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; failures=$((failures + 1)); }
check() { name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

dry() { env LIDAWAKE_DRY_RUN=1 LIDAWAKE_HOME="$FAKE_HOME" "$@"; }

# 1. Syntax
for s in $SCRIPTS; do
    check "sh -n Resources/$s" sh -n "$RES/$s"
done
check "sh -n scripts/selftest.sh" sh -n "$0"

# 2. shellcheck
if command -v shellcheck >/dev/null 2>&1; then
    for s in $SCRIPTS; do
        if out=$(shellcheck -s sh "$RES/$s" 2>&1); then pass "shellcheck Resources/$s"; else fail "shellcheck Resources/$s" "$out"; fi
    done
    if out=$(shellcheck -s sh "$0" 2>&1); then pass "shellcheck scripts/selftest.sh"; else fail "shellcheck scripts/selftest.sh" "$out"; fi
else
    printf 'SKIP  shellcheck not installed\n'
fi

# 3. Sudoers rule
ME=$(id -un)
SUDOERS="$TMP/sudoers"
if out=$(dry LIDAWAKE_SUDOERS_PATH="$SUDOERS" sh "$RES/install-helper.sh" "$ME" 2>&1); then
    pass "install-helper.sh dry run"
else
    fail "install-helper.sh dry run" "$out"
fi
if [ -f "$SUDOERS" ] && /usr/sbin/visudo -cf "$SUDOERS" >/dev/null 2>&1; then
    pass "visudo -cf on generated sudoers rule"
else
    fail "visudo -cf on generated sudoers rule"
fi
expected="$ME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
rules=$(grep -v '^#' "$SUDOERS" 2>/dev/null | grep -v '^[[:space:]]*$')
if [ "$rules" = "$expected" ]; then
    pass "sudoers rule allows only the two pmset commands for $ME"
else
    fail "sudoers rule allows only the two pmset commands for $ME" "got: $rules"
fi
cp "$SUDOERS" "$TMP/sudoers.first" 2>/dev/null
dry LIDAWAKE_SUDOERS_PATH="$SUDOERS" sh "$RES/install-helper.sh" "$ME" >/dev/null 2>&1 &&
    cmp -s "$SUDOERS" "$TMP/sudoers.first"
check "install-helper.sh is idempotent" [ $? -eq 0 ]

for bad in "" "Root" "1abc" "a b" "a;b" "../x" "$(printf 'kg\nroot')"; do
    if dry sh "$RES/install-helper.sh" "$bad" >/dev/null 2>&1; then
        fail "install-helper.sh rejects username '$bad'"
    else
        pass "install-helper.sh rejects username '$(printf '%s' "$bad" | tr '\n' '|')'"
    fi
done
if dry sh "$RES/install-helper.sh" lidawake_no_such_user >/dev/null 2>&1; then
    fail "install-helper.sh rejects unknown user"
else
    pass "install-helper.sh rejects unknown user"
fi
if [ "$(id -u)" -ne 0 ]; then
    # Without dry run, as a normal user, both root scripts must refuse before doing anything.
    for s in install-helper.sh uninstall-helper.sh; do
        if env -u LIDAWAKE_DRY_RUN sh "$RES/$s" "$ME" >/dev/null 2>&1; then
            fail "$s refuses to run without root"
        else
            pass "$s refuses to run without root"
        fi
    done
fi

out1=$(dry sh "$RES/uninstall-helper.sh" "$ME" 2>&1); rc1=$?
out2=$(dry sh "$RES/uninstall-helper.sh" "$ME" 2>&1); rc2=$?
if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && [ "$out1" = "$out2" ] &&
    printf '%s\n' "$out1" | grep -qx 'DRY RUN: /usr/bin/pmset -a disablesleep 0'; then
    pass "uninstall-helper.sh dry run, twice"
else
    fail "uninstall-helper.sh dry run, twice" "$out1"
fi

# 4. LaunchAgent
if out=$(dry sh "$RES/install-watchdog.sh" 2>&1); then pass "install-watchdog.sh dry run"; else fail "install-watchdog.sh dry run" "$out"; fi
if out=$(dry sh "$RES/install-watchdog.sh" 2>&1); then pass "install-watchdog.sh dry run again (idempotent)"; else fail "install-watchdog.sh dry run again (idempotent)" "$out"; fi
check "plutil -lint on generated plist" plutil -lint -s "$PLIST"
pval() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }
check "plist Label" [ "$(pval Label)" = "$LABEL" ]
check "plist StartInterval is 60" [ "$(pval StartInterval)" = 60 ]
check "plist RunAtLoad is true" [ "$(pval RunAtLoad)" = true ]
check "plist ProgramArguments[0] is /bin/sh" [ "$(pval ProgramArguments.0)" = /bin/sh ]
check "plist ProgramArguments[1] is the copied watchdog path, space intact" \
    [ "$(pval ProgramArguments.1)" = "$SUPPORT/watchdog.sh" ]
check "plist ProgramArguments has 2 entries" [ "$(plutil -extract ProgramArguments raw -o - "$PLIST" 2>/dev/null)" = 2 ]
check "plist StandardOutPath and StandardErrorPath are /dev/null" \
    [ "$(pval StandardOutPath)$(pval StandardErrorPath)" = /dev/null/dev/null ]
check "watchdog copied with mode 755" [ "$(stat -f %Lp "$SUPPORT/watchdog.sh" 2>/dev/null)" = 755 ]

# 5. Watchdog
NOAPP=lidawake-selftest-no-such-process
rm -f "$MARKER"
out=$(dry LIDAWAKE_PROCESS_NAME=$NOAPP sh "$RES/watchdog.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then pass "watchdog: no marker prints nothing"; else fail "watchdog: no marker prints nothing" "rc=$rc out=$out"; fi

: >"$MARKER"
out=$(dry LIDAWAKE_PROCESS_NAME=$NOAPP sh "$RES/watchdog.sh" 2>&1); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "DRY RUN: /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0" ] && [ ! -e "$MARKER" ]; then
    pass "watchdog: marker present, app not running restores sleep and clears marker"
else
    fail "watchdog: marker present, app not running restores sleep and clears marker" "rc=$rc out=$out"
fi
out=$(dry LIDAWAKE_PROCESS_NAME=$NOAPP sh "$RES/watchdog.sh" 2>&1)
check "watchdog: second run after reset prints nothing" [ -z "$out" ]

: >"$MARKER"
sleep 30 &
sleeper=$!
out=$(dry LIDAWAKE_PROCESS_NAME=sleep sh "$RES/watchdog.sh" 2>&1)
kill "$sleeper" 2>/dev/null
if [ -z "$out" ] && [ -e "$MARKER" ]; then pass "watchdog: marker present, app running does nothing"; else fail "watchdog: marker present, app running does nothing" "out=$out"; fi
rm -f "$MARKER"

# 6. Log format
if [ -f "$LOGFILE" ] && ! grep -Ev '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4} \[(setup|watchdog)\] .+$' "$LOGFILE" >/dev/null; then
    pass "log lines match the shared format ($(wc -l <"$LOGFILE" | tr -d ' ') lines)"
else
    fail "log lines match the shared format"
fi
check "watchdog log line written" grep -q '\[watchdog\] app not running, restored normal sleep$' "$LOGFILE"

# 7. Uninstall watchdog
out1=$(dry sh "$RES/uninstall-watchdog.sh" 2>&1); rc1=$?
out2=$(dry sh "$RES/uninstall-watchdog.sh" 2>&1); rc2=$?
if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ] && [ "$out1" = "$out2" ] && [ ! -e "$PLIST" ] && [ ! -e "$SUPPORT/watchdog.sh" ]; then
    pass "uninstall-watchdog.sh dry run, twice"
else
    fail "uninstall-watchdog.sh dry run, twice" "$out1"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "selftest: all checks passed"
    exit 0
fi
echo "selftest: $failures check(s) failed"
exit 1
