"""Synthesizes the launch video score to public/score.wav. No samples, no third-party audio.

Event times are read from the T block in src/theme.ts (frames at 30 fps)."""
import re
import numpy as np
import wave
from pathlib import Path
from types import SimpleNamespace

SR = 48000
FPS = 30
_theme = Path(__file__).resolve().parent.parent / 'src' / 'theme.ts'
_block = re.search(r'export const T = \{(.*?)\};', _theme.read_text(), re.S).group(1)
T = SimpleNamespace(**{k: int(v) for k, v in re.findall(r'(\w+):\s*(\d+)', _block)})
DUR = T.total / FPS
N = int(DUR * SR)
rng = np.random.default_rng(7)
t_all = np.arange(N) / SR


def sec(frame):
    return frame / FPS


def env(n, attack, release, sustain=1.0):
    e = np.ones(n) * sustain
    a = min(n, int(attack * SR))
    r = min(n - a, int(release * SR))
    if a:
        e[:a] = np.linspace(0, sustain, a) ** 2
    if r:
        e[n - r:] = e[n - r:] * np.linspace(1, 0, r) ** 2
    return e


def onepole(x, cutoff):
    if np.isscalar(cutoff):
        cutoff = np.full(len(x), cutoff)
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff, passes=2):
    # Frequency-domain brickwall-ish lowpass with a soft knee; fine for pads.
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / (1 + (f / cutoff) ** (2 * passes))
    return np.fft.irfft(X, len(x))


def tone(freq, dur, amp=0.1, attack=0.02, release=0.3, harmonics=(1, 0.35, 0.12, 0.05), detune=0.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, h in enumerate(harmonics, start=1):
        for d in ((-detune, detune) if detune else (0,)):
            out += h * np.sin(2 * np.pi * freq * k * (1 + d) * t + rng.uniform(0, 6.28))
    return out * env(n, attack, release) * amp / (2 if detune else 1)


def add(buf, start, sig, pan=0.0):
    i = int(start * SR)
    if i >= N:
        return
    sig = sig[: N - i]
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    buf[0, i:i + len(sig)] += sig * l
    buf[1, i:i + len(sig)] += sig * r


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


pad = np.zeros((2, N))
fx = np.zeros((2, N))
drums = np.zeros((2, N))

# ---- Chords. D major colour, slow and open. ----
D9 = [50, 57, 62, 64, 66, 69]
Bm9 = [47, 54, 62, 66, 69, 73]
G69 = [43, 50, 59, 62, 64, 69]
A6 = [45, 52, 61, 64, 66, 69]
Em9 = [40, 52, 59, 62, 66, 67]
night1 = [38, 50, 57, 62, 64]  # low, wide
night2 = [35, 47, 54, 62, 66]


def chord(buf, start, dur, notes, amp=0.05, attack=1.2, release=1.6, bright=1.0):
    for j, m in enumerate(notes):
        h = (1, 0.3 * bright, 0.1 * bright, 0.04 * bright)
        add(buf, start, tone(midi(m), dur, amp * (1.2 if j == 0 else 1), attack, release, h, detune=0.0015), pan=(j / max(1, len(notes) - 1) - 0.5) * 0.8)


# Opening: soft, expectant, until the lid shuts.
chord(pad, 0.0, sec(T.close1) + 0.6, D9, 0.045, 0.6, 0.5)
chord(pad, sec(T.close1) * 0.5, sec(T.close1) * 0.5 + 0.6, Bm9, 0.025, 0.6, 0.5)
# Lid closes and the Mac sleeps: the music stops with it. Only room tone until the lid opens.
# Lid opens: one rising note, then the build to the click.
chord(pad, sec(T.reopen), sec(T.click - T.reopen), G69, 0.04, 1.4, 0.3, bright=0.7)
# Click: everything lands.
chord(pad, sec(T.click), sec(T.closed2 - T.click) + 1.2, D9, 0.055, 0.05, 1.5, bright=1.2)
# Night: wide and low, steady.
night = sec(T.nightEnd - T.closed2)
chord(pad, sec(T.closed2) - 0.3, night * 0.6, night1, 0.05, 1.2, 2.0, bright=0.5)
chord(pad, sec(T.closed2) + night * 0.45, night * 0.55, night2, 0.05, 1.4, 1.6, bright=0.5)
# Morning: bright, a little higher.
chord(pad, sec(T.open3) - 0.6, sec(T.stats - T.open3) + 1.4, [50, 62, 66, 69, 74, 76], 0.05, 1.0, 1.2, bright=1.3)
# Proof and guardrails: confident movement.
SWAP = T.password + 58  # the password card swaps to its second line here (Cards.tsx)
prog = [(T.stats, Bm9), (T.stats + 50, G69), (T.guard, D9), (T.guard + 50, A6), (T.password, G69), (SWAP, Em9)]
for k, (fr, ch) in enumerate(prog):
    nxt = prog[k + 1][0] if k + 1 < len(prog) else T.end
    chord(pad, sec(fr), sec(nxt - fr) + 0.5, ch, 0.045, 0.15, 0.5, bright=1.1)
# End: resolve and ring out.
chord(pad, sec(T.end), DUR - sec(T.end), [38, 50, 57, 62, 66, 69, 74], 0.055, 0.08, 3.2, bright=1.0)

# Sub bass under the sections that move.
for fr, m, d in [(T.click, 38, sec(T.closed2 - T.click)), (T.stats, 35, 1.7), (T.stats + 50, 31, 1.7), (T.guard, 38, 1.7),
                 (T.guard + 50, 33, 1.7), (T.password, 31, 1.9), (SWAP, 28, 1.9), (T.end, 26, sec(T.total - T.end))]:
    add(pad, sec(fr), tone(midi(m + 12), d, 0.09, 0.02, 0.6, (1, 0.15)), 0)

# ---- Sound effects. ----

def thud(amp=0.5):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (70 * np.exp(-t * 9) + 45) * t) * np.exp(-t * 14)
    click = lowpass_fast(rng.standard_normal(n), 1800) * np.exp(-t * 90) * 0.5
    return (body + click) * amp


def ui_click(amp=0.35):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    hp = noise - onepole(noise, 2500)
    return (hp * np.exp(-t * 260) * 0.8 + np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 180) * 0.25) * amp


def swell(dur, amp=0.12, f0=300, f1=4000):
    n = int(dur * SR)
    noise = rng.standard_normal(n)
    cut = np.geomspace(f0, f1, n)
    y = onepole(noise, cut)
    return y * env(n, dur * 0.85, dur * 0.15) * amp


def tick(amp=0.08, freq=3200):
    n = int(0.03 * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t) * np.exp(-t * 300) * amp


def chime(m, amp=0.06):
    return tone(midi(m), 2.5, amp, 0.003, 2.4, (1, 0.0, 0.2, 0.0, 0.05))


# Hinge creak-free lid closes, as soft thuds at the moment the lid meets the base.
add(fx, sec(T.closed1) - 0.02, thud(0.55), 0.1)
add(fx, sec(T.closed2) - 0.02, thud(0.45), -0.1)
# Lid opens: air.
add(fx, sec(T.reopen), swell(0.9, 0.05, 200, 2500), 0)
add(fx, sec(T.open3), swell(1.0, 0.05, 200, 2500), 0)
# The push into the screen.
add(fx, sec(T.flatIn) - 1.2, swell(1.3, 0.07, 300, 6000), 0)
# The click itself.
add(fx, sec(T.click) - 0.03, ui_click(0.55), 0.35)
add(fx, sec(T.click), chime(81, 0.05), 0.35)
add(fx, sec(T.click) + 0.09, chime(86, 0.035), 0.35)

# Night: a soft tick each half-second while the real heartbeats scroll, and a chime on each new hour.
night_start = sec(T.closed2 + 16)
night_end = sec(T.nightEnd - 70)  # NightHud's clock runs from closed2 + 16 to nightEnd - 70
x = night_start
k = 0
while x < night_end:
    add(fx, x, tick(0.05 if k % 2 else 0.075, 3000 if k % 2 else 3600), 0.3 if k % 2 else -0.3)
    x += 0.25
    k += 1
# 22:54 to 07:25 crosses 8 hours: 23:00 ... 07:00. Times follow the eased clock in NightHud.
def eased(u):
    # Easing.bezier(0.65, 0, 0.35, 1) inverse by search
    def bez(s):
        cx1, cx2 = 0.65, 0.35
        bx = 3 * cx1 * s * (1 - s) ** 2 + 3 * cx2 * s ** 2 * (1 - s) + s ** 3
        by = 3 * 0 * s * (1 - s) ** 2 + 3 * 1 * s ** 2 * (1 - s) + s ** 3
        return bx, by
    lo, hi = 0.0, 1.0
    for _ in range(50):
        mid = (lo + hi) / 2
        if bez(mid)[1] < u:
            lo = mid
        else:
            hi = mid
    return bez(lo)[0]

for h in range(8):
    minute_index = (60 - 54) + 60 * h  # 23:00 is 6 minutes after 22:54
    u = minute_index / 511
    when = night_start + eased(u) * (night_end - night_start)
    add(fx, when, chime(74 if h % 2 else 69, 0.05), 0)

# Guardrail and card hits.
for fr in [T.stats, T.guard, T.password, SWAP]:
    add(fx, sec(fr), thud(0.18), 0)
    add(fx, sec(fr) - 0.4, swell(0.45, 0.035, 500, 7000), 0)
add(fx, sec(T.end), chime(86, 0.05), 0)
add(fx, sec(T.end) + 0.12, chime(90, 0.04), 0)

# Light pulse under the proof and guardrails: shaker on eighths.
x = sec(T.stats)
k = 0
while x < sec(T.end):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    s = rng.standard_normal(n)
    s = s - onepole(s, 6000)
    add(drums, x, s * np.exp(-t * (70 if k % 2 else 45)) * (0.025 if k % 2 else 0.04), 0.2)
    x += 0.25
    k += 1

# Room tone so the silence after the first lid close still has air.
room = lowpass_fast(rng.standard_normal(N), 600) * 0.004
pad += room

# ---- Reverb: convolve the pad and fx with a decaying noise tail. ----

def reverb(x, seconds=3.2, wet=0.35):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t * 3.0 / seconds * 2.2)
    ir = lowpass_fast(ir, 5000)
    ir /= np.sqrt(np.sum(ir ** 2))
    out = np.zeros_like(x)
    for c in range(2):
        L = len(x[c]) + n
        size = 1 << (L - 1).bit_length()
        y = np.fft.irfft(np.fft.rfft(x[c], size) * np.fft.rfft(ir, size), size)[: len(x[c])]
        out[c] = x[c] * (1 - wet) + y * wet
    return out

mix = reverb(pad, 3.5, 0.4) + reverb(fx, 2.0, 0.25) + drums
# Gentle master fade in and out.
fade = np.ones(N)
fi = int(0.4 * SR)
fade[:fi] = np.linspace(0, 1, fi)
fo = int(2.0 * SR)
fade[-fo:] = np.linspace(1, 0, fo) ** 1.5
mix *= fade
peak = np.max(np.abs(mix))
mix = mix / peak * 0.89
# Soft saturation lifts the level without hard clipping.
mix = np.tanh(mix * 1.9) / np.tanh(1.9) * 0.92
pcm = (mix.T * 32767).astype(np.int16)
with wave.open('public/score.wav', 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('wrote public/score.wav', round(DUR, 2), 's, peak before norm', round(float(peak), 3))
