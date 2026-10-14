#!/bin/bash
# Builds LidAwake from this checkout and installs it in /Applications. Needs no sudo.
# The password prompt comes later, from the app, when you click "Allow once".
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "LidAwake needs Apple's Command Line Tools to build. Run: xcode-select --install" >&2
    echo "Then run this script again." >&2
    exit 1
fi

./build.sh

if pgrep -x LidAwake >/dev/null; then
    # Quitting turns closed-lid mode off and restores normal sleep.
    osascript -e 'tell application "LidAwake" to quit' >/dev/null 2>&1 || true
    sleep 2
fi

rm -rf /Applications/LidAwake.app
ditto build/LidAwake.app /Applications/LidAwake.app
open /Applications/LidAwake.app

echo
echo "LidAwake is in /Applications and running. Look for the cup in the menu bar."
echo "First time: click the cup, then \"Allow once\", and enter your Mac password."
