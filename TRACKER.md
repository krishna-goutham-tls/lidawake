# Tracker

## Now: MVP test on Krishna's Mac

Ship criteria are in `../brainstorming/mvp-plan.md`. Tick each one after it passes on the real Mac.

- [x] 1. Setup takes one admin password prompt (2026-10-13, 0.2.0 fresh install)
- [x] 2. 30 minutes, lid closed, on battery: heartbeat lines show `lid=closed`, agent output keeps coming (2026-10-13 22:54 to 2026-10-14 07:25, 512 heartbeats with no gap, battery 80% to 68%, heat nominal, agents kept working)
- [ ] 3. Switch off, lid closed: the Mac sleeps as usual
- [ ] 4. Battery cutoff stops the switch and sleeps the Mac
- [ ] 5. Forced heat state stops the switch and sleeps the Mac
- [ ] 6. `kill -9` while on: the watchdog restores sleep within about 60 s
- [ ] 7. Restart while on: sleep is restored after login
- [x] 8. Quit restores normal sleep (2026-10-14, SleepDisabled back to 0)
- [ ] 9. Remove permission deletes the sudoers rule and the LaunchAgent
- [ ] 10. No idle CPU, no network calls

## Next, after the MVP passes

- Pick the real name
- Open at login
- Auto-off when agents go quiet (differentiator candidate)
- Developer ID signing and notarization before strangers install it
