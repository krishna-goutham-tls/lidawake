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

## Launch (open source, 2026-10-14)

- [x] Public repo `krishna-goutham-tls/lidawake`, MIT, README with install line, demo GIF, proof and trust section
- [x] `scripts/install.sh`: build and install with no sudo
- [ ] Release zip v0.4.0 on GitHub
- [ ] Social preview image set in repo settings (`docs/social-preview.png`, Krishna)
- [ ] Launch post on X

## Next, after the MVP passes

- Pick the real name
- Open at login
- Heat stop from real temperature, not only macOS thermal state (Lidless #34: thermal state stayed nominal while a closed Mac got very hot). See `../brainstorming/user-pain-research.md`
- Auto-off when agents go quiet (taken by LidRun, Adrafinil, Hold My Lid)
- Developer ID signing and notarization before strangers install it
