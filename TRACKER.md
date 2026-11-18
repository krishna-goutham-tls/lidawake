# Tracker

## Now: MVP test on Krishna's Mac

Ship criteria are in `../brainstorming/mvp-plan.md`. Tick each one after it passes on the real Mac.

- [x] 1. Setup takes one admin password prompt (2026-10-13, 0.2.0 fresh install)
- [x] 2. 30 minutes, lid closed, on battery: heartbeat lines show `lid=closed`, agent output keeps coming (2026-10-13 22:54 to 2026-10-14 07:25, 512 heartbeats with no gap, battery 80% to 68%, heat nominal, agents kept working)
- [ ] 3. Switch off, lid closed: the Mac sleeps as usual
- [ ] 4. Battery cutoff stops the switch and sleeps the Mac
- [ ] 5. Forced heat state stops the switch and sleeps the Mac
- [ ] 6. `kill -9` while on: the watchdog restores sleep within about 60 s. 0.4.0: with the lid shut it also sleeps the Mac (README test 6b)
- [ ] 7. Restart while on: sleep is restored after login
- [x] 8. Quit restores normal sleep (2026-10-14, SleepDisabled back to 0)
- [ ] 9. Remove permission deletes the sudoers rule and the LaunchAgent
- [ ] 10. No idle CPU, no network calls. 0.3.0 failed: about 10% CPU while on, from the cup animation still running in the closed panel. 0.3.1 stops it when the panel closes (0% in a repro). Re-measure on the installed 0.4.0 while on: `ps -o time= -p $(pgrep -x LidAwake)` twice, 10 s apart
- [ ] 11. Lid report (0.4.0): open the lid after 10 min closed while on, unlock, and a panel says how long it stayed awake (README test 11)
- [ ] 12. Lid lock check (0.4.0): `sudo pmset -a disablesleep 0` while on is undone within 30 s (README test 12)

## Updates

- [x] In-app updater (2026-11-18, not released): daily GitHub check, update window, one-click install with a Developer ID check, "Check for updates…" in the menu. Tested against the real GitHub release
- [ ] First release with the updater (needs Krishna's go). Copies from before it never update themselves

## Activity window (0.6.0, built 2026-11-18, not released)

- [x] Window "While the lid was closed": time awake, a row per agent, a macOS row, battery, earlier lid closes, Copy image. Reads the log, so old nights show too
- [x] Heartbeat logs agent and macOS processor time (`agents=`, `macos=`)
- [ ] 13. One real night on Krishna's Mac with 0.6.0: the agent rows match what the agents did (README test 13)
- [ ] Check the "working" threshold (0.5 processor seconds a minute) against that night. Measured on 2026-11-18 over 14 minutes only: a Claude Code session in a turn used 0.54 to 1.4, idle ones 0.1 to 0.45, so the margin is small
- [ ] Pointer line under the chart and Copy image, tried by hand
- [ ] Release 0.6.0 (needs Krishna's go)
- Left out for now: project name per agent (a client name could land in a posted image), data sent and received, apps no agent started

## Launch (open source, 2026-10-14)

- [x] Public repo `krishna-goutham-tls/lidawake`, MIT, README with install line, demo GIF, proof and trust section
- [x] `scripts/install.sh`: build and install with no sudo
- [x] Release zip v0.4.0 on GitHub (2026-10-14, `LidAwake.zip`)
- [x] Social preview image set in repo settings (`docs/social-preview.png`, seen 2026-11-03)
- [ ] Launch post on X

## Next, after the MVP passes

- Pick the real name
- Open at login
- Heat stop from real temperature, not only macOS thermal state (Lidless #34: thermal state stayed nominal while a closed Mac got very hot). See `../brainstorming/user-pain-research.md`
- Auto-off when agents go quiet
- Developer ID signing and notarization before strangers install it
