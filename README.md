# LidAwake

A menu bar switch that keeps a MacBook running with the lid closed, so CLI agents such as Claude Code, Droid and Codex keep working. It turns itself off and sleeps the Mac at a battery cutoff or when the Mac gets too hot.

Version 0.2.0. macOS 14 or later. Apple silicon and Intel. No network calls.

## Build

```sh
./build.sh                  # makes build/LidAwake.app, ad-hoc signed
sh scripts/selftest.sh      # checks the scripts, no root, no system changes
build/LidAwake.app/Contents/MacOS/LidAwake --selftest

# Render a window state to PNG without touching sleep settings
build/LidAwake.app/Contents/MacOS/LidAwake --preview-guide setUp --snapshot /tmp/setup.png
#   states: setUp, turnOn, waiting, success, successOn, info (add --helper-ready)
build/LidAwake.app/Contents/MacOS/LidAwake --preview-hud on --snapshot /tmp/hud.png
```

## Install

1. Copy `build/LidAwake.app` to `/Applications`. Setup runs the bundled scripts as root, so keep the app somewhere only an admin can change.
2. Open it. A cup icon appears in the menu bar, and a welcome window opens the first time.
3. Click **Allow closed-lid mode** and enter your Mac password once. The window confirms and closes by itself.

Setup adds `/etc/sudoers.d/lidawake`, which lets your user run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. It also adds a watchdog LaunchAgent at `~/Library/LaunchAgents/space.thelaunch.lidawake.watchdog.plist`.

## Use

Click the cup. It starts steaming, and a small bubble says "Awake. Safe to close the lid." Close the lid. Click the cup again to turn it off.

Right-click the cup, or Control-click it, for settings: battery cutoff, How it works, the log, removing the permission, and Quit.

If closed-lid mode is not set up yet, clicking the cup opens the welcome window with **Allow and turn on**, which sets it up and turns it on in one step.

It switches off and sleeps the Mac when:

- it is on battery and the battery reaches the cutoff (default 20%, change it under **Stop at battery**)
- macOS reports a serious or critical thermal state

Keep the Mac on a hard, ventilated surface. Do not run it inside a bag.

## What can go wrong

- Keeping the Mac awake does not keep it online. If you leave your Wi-Fi, cloud-backed agents stop.
- An agent waiting for a permission prompt or hitting a usage limit stays stuck, lid open or closed.
- If the Mac restarts while the switch is on, it stays awake at the login screen until you log in. The watchdog restores normal sleep right after login.

## Check that it worked

Every minute while the switch is on, the app writes a line to `~/Library/Logs/LidAwake.log`:

```
2026-10-13T23:10:00+0530 [app] heartbeat lid=closed battery=81% power=battery thermal=nominal sleepDisabled=1
```

Lines with `lid=closed` one minute apart prove the Mac stayed awake with the lid shut. **Open log** in the menu opens the file.

## MVP test, on your Mac

| # | Do this | Pass when |
|---|---|---|
| 1 | Set up closed-lid mode | One password prompt. The menu shows **Remove closed-lid permission** |
| 2 | Start a long agent task. Switch on. Unplug. Close the lid for 30 min on a desk | The log has `lid=closed` heartbeats about every minute, and the agent kept working |
| 3 | Switch off. Close the lid for 2 min | No heartbeats. `pmset -g \| grep SleepDisabled` prints nothing or `0` |
| 4 | On battery, set **Stop at battery** above the current level, switch on | Within 30 s the switch turns off and the Mac sleeps. The log says why |
| 5 | `defaults write space.thelaunch.lidawake debugForceThermal -string serious`, then switch on | The switch refuses to start, saying the Mac is too hot. Switch on first, then run the command, and within 30 s it stops and sleeps. Clear it with `defaults delete space.thelaunch.lidawake debugForceThermal` |
| 6 | Switch on, then `pkill -9 -x LidAwake` | Within about 60 s the log shows `[watchdog] app not running, restored normal sleep` |
| 7 | Switch on, then restart the Mac | After login, `pmset -g \| grep SleepDisabled` prints nothing or `0` |
| 8 | Switch on, then **Quit LidAwake** | `SleepDisabled` is back to `0` |
| 9 | **Remove closed-lid permission** | `/etc/sudoers.d/lidawake` and the LaunchAgent are gone |
| 10 | Leave it off for 10 min | Activity Monitor shows 0% CPU |

## Uninstall

Click **Remove closed-lid permission**, quit the app, and delete it from `/Applications`. If the app is gone already:

```sh
sudo rm -f /etc/sudoers.d/lidawake && sudo pmset -a disablesleep 0
launchctl bootout gui/$(id -u)/space.thelaunch.lidawake.watchdog
rm -f ~/Library/LaunchAgents/space.thelaunch.lidawake.watchdog.plist
rm -rf ~/Library/Application\ Support/LidAwake
```
