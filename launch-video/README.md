# LidAwake launch video

53.4 seconds, 1920x1080, 30 fps. Remotion with a three.js MacBook built in code. The score is synthesized, no samples.

```sh
npm install
python3 tools/score.py                       # writes public/score.wav
npx remotion render src/index.ts LaunchVideo out/lidawake-launch.mp4 --gl=angle --crf=16 --timeout=120000
ffmpeg -i out/lidawake-launch.mp4 -c:v copy -af "loudnorm=I=-15:TP=-1.5:LRA=11,aresample=48000" \
  -c:a aac -b:a 192k -movflags +faststart out/lidawake-launch-master.mp4   # raw mix peaks above 0 dBFS
npx remotion studio src/index.ts             # preview and scrub
for t in A B C; do npx remotion still src/index.ts Thumb$t out/thumbs/thumb-$t.png --gl=angle --timeout=120000; done
```

- Shot timing lives in `src/theme.ts` (`T`). `tools/score.py` reads that block, so rerun it after a timing change.
- The night numbers come from the real log of 2026-10-13 (`src/night-log.ts`): 512 heartbeats, 22:54 to 07:25, all lid closed, on battery, heat nominal.
- Icons are SF Symbols rendered by `tools/symbols.swift` (`swiftc -O tools/symbols.swift -o /tmp/s && /tmp/s public`).
- Thumbnails (`src/Thumbnails.tsx`) are 1920x1080 for X and LinkedIn: A the night shot, B the real log, C the problem then the fix (day). Every line is one plain sentence. Words stay out of the centre (play button) and the bottom-left corner (X duration badge).
- The terminal is an illustration of an agent run. Every claim in the captions is true of LidAwake 0.4.0. The setup panel and menu bar in the password scene copy the real panel.
