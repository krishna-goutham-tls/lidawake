#!/bin/bash
# Installs LidAwake in /Applications. Needs no sudo.
#
#   scripts/install.sh                 downloads the latest release zip from GitHub
#   scripts/install.sh --from-source   builds this checkout with Apple's Command Line Tools
#
# GitHub counts each release download, which is the only install count this project has.
# The app itself never goes online. The password prompt comes later, from the app.
set -euo pipefail

cd "$(dirname "$0")/.."

URL="https://github.com/krishna-goutham-tls/lidawake/releases/latest/download/LidAwake.zip"

if [ "${1:-}" = "--from-source" ]; then
    if ! xcrun --find swiftc >/dev/null 2>&1; then
        echo "Building needs Apple's Command Line Tools. Run: xcode-select --install" >&2
        echo "Then run this script again." >&2
        exit 1
    fi
    ./build.sh
    APP="build/LidAwake.app"
else
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    echo "==> downloading the latest LidAwake release"
    if ! curl -fsSL "$URL" -o "$TMP/LidAwake.zip"; then
        echo "The download failed. To build it on this Mac instead, run: $0 --from-source" >&2
        exit 1
    fi
    ditto -x -k "$TMP/LidAwake.zip" "$TMP"
    APP="$TMP/LidAwake.app"
    if [ ! -d "$APP" ]; then
        echo "The release zip has no LidAwake.app inside. Try: $0 --from-source" >&2
        exit 1
    fi
fi

if pgrep -x LidAwake >/dev/null; then
    # Quitting turns closed-lid mode off and restores normal sleep.
    osascript -e 'tell application "LidAwake" to quit' >/dev/null 2>&1 || true
    sleep 2
fi

rm -rf /Applications/LidAwake.app
ditto "$APP" /Applications/LidAwake.app
open /Applications/LidAwake.app

echo
echo "LidAwake is in /Applications and running. Look for the cup in the menu bar."
echo "First time: click the cup, then \"Allow once\", and enter your Mac password."
