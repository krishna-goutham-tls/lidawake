import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { easeInOut, easeOut, Mono, prog, Rise } from '../kit';
import { NIGHT } from '../night-log';
import { SetupPanel } from '../Panels';
import { color, font, T } from '../theme';

/** 0: the problem, type only. */
export function Problem() {
  return (
    <AbsoluteFill style={{ background: color.paper, justifyContent: 'center', paddingLeft: 150 }}>
      <Rise text="Closing the lid" at={4} size={140} />
      <Rise text="stops your agents?" at={10} size={140} />
      <div style={{ marginTop: 36 }}>
        <Rise text="Well, not anymore." at={T.problemB - 6} size={140} tone={color.blue} />
      </div>
    </AbsoluteFill>
  );
}

/** Captions laid over the 3D shots. Frame is global. */
export function Caption3D({ offset }: { offset: number }) {
  const f = useCurrentFrame() + offset;
  const box = (child: React.ReactNode, a: number, b: number, top = false) => {
    if (f < a - 2 || f > b + 12) return null;
    return (
      <AbsoluteFill style={{ justifyContent: top ? 'flex-start' : 'flex-end', padding: top ? '120px 150px 0' : '0 150px 110px' }}>{child}</AbsoluteFill>
    );
  };
  const local = (a: number) => a - offset;
  return (
    <>
      {box(
        <>
          <Rise text="When you close the lid, the Mac sleeps" at={local(T.closed1 - 6)} out={local(T.reopen - 6)} size={92} />
          <Rise text="and so do your agents." at={local(T.closed1 + 16)} out={local(T.reopen - 6)} size={92} />
        </>,
        T.closed1 - 6,
        T.reopen,
        true,
      )}
      {box(<Rise text="Then close the lid." at={local(T.flatOut + 8)} out={local(T.closed2 + 4)} size={96} />, T.flatOut + 8, T.closed2 + 4)}
    </>
  );
}

/** The night: a real clock, real heartbeats, real battery. Frame is global. */
export function NightHud({ offset }: { offset: number }) {
  const f = useCurrentFrame() + offset;
  const a = T.closed2 + 16;
  const b = T.nightEnd - 92;
  const t = interpolate(f, [a, b], [0, NIGHT.length - 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: easeInOut });
  const i = Math.round(t);
  const [clock, battery] = NIGHT[i];
  // Only on a dark sky, so the white type never sits on the grey middle of the fade.
  const vis = prog(f, T.closed2 + 36, T.closed2 + 52) * (1 - prog(f, T.nightEnd - 78, T.nightEnd - 62));
  if (vis <= 0) return null;
  const lines = NIGHT.slice(Math.max(0, i - 5), i + 1);
  return (
    <AbsoluteFill style={{ opacity: vis, color: '#fff' }}>
      <div style={{ position: 'absolute', left: 150, top: 120 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <Img src={staticFile('cup-on-white.png')} style={{ height: 34, opacity: 0.85 }} />
          <Mono size={28} tone="rgba(214,226,255,0.7)">lid closed · on battery</Mono>
        </div>
        <div style={{ fontFamily: font.sans, fontWeight: 600, fontSize: 210, letterSpacing: '-0.05em', lineHeight: 1, marginTop: 12, fontVariantNumeric: 'tabular-nums' }}>
          {clock}
        </div>
      </div>
      <div style={{ position: 'absolute', right: 150, top: 150, textAlign: 'right' }}>
        <Mono size={28} tone="rgba(214,226,255,0.7)">battery</Mono>
        <div style={{ fontFamily: font.sans, fontWeight: 600, fontSize: 96, letterSpacing: '-0.04em', marginTop: 12, fontVariantNumeric: 'tabular-nums' }}>
          {battery}%
        </div>
      </div>
      <div style={{ position: 'absolute', left: 150, bottom: 96 }}>
        {lines.map(([c, bat], k) => (
          <Mono key={c} size={22} tone={`rgba(190,205,240,${0.25 + 0.6 * ((k + 1) / lines.length)})`} style={{ lineHeight: '34px' }}>
            {c} heartbeat lid=closed battery={bat}% power=battery thermal=nominal
          </Mono>
        ))}
      </div>
    </AbsoluteFill>
  );
}

function Stat({ big, label, at }: { big: string; label: string; at: number }) {
  const f = useCurrentFrame();
  const p = prog(f, at, at + 18);
  return (
    <div style={{ opacity: p, transform: `translateY(${(1 - p) * 40}px)` }}>
      <div style={{ fontFamily: font.sans, fontWeight: 700, fontSize: 150, letterSpacing: '-0.05em', color: color.ink, lineHeight: 1, whiteSpace: 'nowrap' }}>
        {big}
      </div>
      <div style={{ fontFamily: font.sans, fontSize: 34, color: color.mist, marginTop: 18, maxWidth: 440, lineHeight: 1.25 }}>{label}</div>
    </div>
  );
}

/** Real numbers from the 2026-10-13 run. */
export function Stats() {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: color.paper, padding: '150px 150px', justifyContent: 'center' }}>
      <Rise text="It keeps working." at={0} size={132} accent={['working']} />
      <Mono size={28} style={{ opacity: prog(f, 16, 30), marginTop: 26 }}>
        one real night · Oct 13–14, 2026 · MacBook, unplugged
      </Mono>
      <div style={{ display: 'flex', gap: 120, marginTop: 80 }}>
        <Stat big="8h 31m" label="lid closed" at={26} />
        <Stat big="512" label="heartbeats, one a minute, no gaps" at={32} />
        <Stat big="12%" label="battery used, 80% to 68%" at={38} />
      </div>
    </AbsoluteFill>
  );
}

function Guard({ icon, line, sub, at, dur }: { icon: string; line: string; sub: string; at: number; dur: number }) {
  const f = useCurrentFrame();
  if (f < at || f >= at + dur) return null;
  const local = f - at;
  const p = prog(local, 0, 16);
  const leave = prog(local, dur - 8, dur, easeInOut);
  return (
    <AbsoluteFill style={{ flexDirection: 'row', alignItems: 'center', padding: '0 150px', gap: 90, opacity: 1 - leave }}>
      <Img
        src={staticFile(icon)}
        style={{ height: 230, opacity: p, transform: `translateX(${(1 - p) * -60}px) scale(${0.9 + 0.1 * p})` }}
      />
      <div style={{ transform: `translateX(${leave * -40}px)` }}>
        <Rise text={line} at={at + 3} size={112} style={{ whiteSpace: 'nowrap' }} />
        <div style={{ opacity: prog(local, 14, 28) }}>
          <Mono size={32} style={{ marginTop: 22 }}>
            {sub}
          </Mono>
        </div>
      </div>
    </AbsoluteFill>
  );
}

/** The guardrails, fast. */
export function Guardrails() {
  return (
    <AbsoluteFill style={{ background: color.paper }}>
      <Guard icon="battery-ink.png" line="Stops at 20% battery." sub="then sleeps your Mac. pick 10, 20, 30 or 50" at={0} dur={60} />
      <Guard icon="thermo-ink.png" line="Stops on a heat warning." sub="when macOS reports serious heat. then sleeps your Mac" at={60} dur={60} />
      <Guard icon="moon-ink.png" line="Off means normal sleep." sub="quit it, and normal sleep is back too" at={120} dur={60} />
    </AbsoluteFill>
  );
}

const BAR_K = 2; // menu bar points to video pixels
const BAR_H = 37 * BAR_K;
const BAR_CUP_X = 1452;
const ink = '#1D1D1F';

function BarIcon({ src, h, x }: { src: string; h: number; x: number }) {
  return <Img src={staticFile(src)} style={{ position: 'absolute', left: x, top: (BAR_H - h) / 2, height: h }} />;
}

/** A light macOS menu bar, faded so the cup and its panel carry the shot. */
function MenuBar({ fade }: { fade: number }) {
  const text = { fontFamily: font.sans, fontSize: 13.5 * BAR_K, color: ink, letterSpacing: '-0.005em' } as const;
  return (
    <div style={{ position: 'absolute', left: 0, top: 0, width: 1920, height: BAR_H }}>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(255,255,255,0.72)', borderBottom: '1px solid rgba(0,0,0,0.06)' }} />
      <div style={{ position: 'absolute', inset: 0, opacity: fade }}>
        <BarIcon src="apple-ink.png" h={34} x={40} />
        <div style={{ position: 'absolute', left: 104, top: 0, height: BAR_H, display: 'flex', alignItems: 'center', gap: 22 * BAR_K, ...text }}>
          <span style={{ fontWeight: 700 }}>Finder</span>
          {['File', 'Edit', 'View', 'Go', 'Window', 'Help'].map((m) => (
            <span key={m}>{m}</span>
          ))}
        </div>
        <BarIcon src="battery75-ink.png" h={26} x={1514} />
        <BarIcon src="wifi-ink.png" h={30} x={1590} />
        <BarIcon src="search-ink.png" h={30} x={1652} />
        <BarIcon src="control-ink.png" h={28} x={1710} />
        <div style={{ position: 'absolute', right: 34, top: 0, height: BAR_H, display: 'flex', alignItems: 'center', ...text, fontWeight: 500 }}>
          Tue 22:52
        </div>
      </div>
      {/* The pressed highlight macOS draws behind the item whose panel is open. */}
      <div style={{ position: 'absolute', left: BAR_CUP_X - 22, top: 6, width: 44, height: BAR_H - 12, borderRadius: 10, background: 'rgba(0,0,0,0.08)' }} />
      <BarIcon src="cup-off-ink.png" h={34} x={BAR_CUP_X - 19} />
    </div>
  );
}

/** Setup, honestly: the panel under the cup, one Mac password. */
export function Password() {
  const f = useCurrentFrame();
  const swapAt = T.swap - T.password;
  const bar = prog(f, 0, 14);
  const p = prog(f, 8, 28);
  const leave = prog(f, swapAt - 8, swapAt, easeInOut);
  const swap = prog(f, swapAt, swapAt + 10, easeInOut);
  return (
    <AbsoluteFill style={{ background: color.paper }}>
      <div style={{ opacity: bar * (1 - swap * 0.6) }}>
        <MenuBar fade={0.45} />
      </div>
      <div
        style={{
          position: 'absolute',
          left: BAR_CUP_X,
          top: BAR_H + 8,
          transformOrigin: '0 0',
          opacity: p * (1 - swap * 0.6),
          transform: `scale(${BAR_K * (0.97 + 0.03 * p)}) translate(-50%, ${(1 - p) * -6}px)`,
        }}
      >
        <SetupPanel />
      </div>
      <div style={{ position: 'absolute', left: 150, top: 400, width: 980 }}>
        <div style={{ opacity: 1 - leave, transform: `translateY(${-leave * 30}px)` }}>
          <Rise text="Set it up once with your Mac password." at={6} size={96} accent={['once']} />
        </div>
        <div style={{ position: 'absolute', top: 0, opacity: swap, transform: `translateY(${(1 - swap) * 30}px)` }}>
          <Rise text="Nothing leaves your Mac." at={swapAt + 2} size={86} style={{ whiteSpace: 'nowrap' }} />
          <Mono size={32} style={{ marginTop: 26, opacity: prog(f, swapAt + 16, swapAt + 30) }}>
            a menu bar app. that's all
          </Mono>
        </div>
      </div>
    </AbsoluteFill>
  );
}

/** The last card. */
export function EndCard() {
  const f = useCurrentFrame();
  const icon = prog(f, 0, 26, easeOut);
  return (
    <AbsoluteFill style={{ background: color.paper, alignItems: 'center', justifyContent: 'center' }}>
      <Img
        src={staticFile('appicon.png')}
        style={{ width: 260, height: 260, opacity: icon, transform: `scale(${0.82 + 0.18 * icon}) translateY(${(1 - icon) * 30}px)` }}
      />
      <div style={{ marginTop: 30 }}>
        <Rise text="LidAwake" at={10} size={150} stagger={0} style={{ textAlign: 'center' }} />
      </div>
      <div style={{ marginTop: 18 }}>
        <Rise text="Close the lid. Keep working." at={22} size={54} weight={500} tone={color.mist} style={{ textAlign: 'center' }} />
      </div>
      <Mono size={24} tone="#9CA3AF" style={{ position: 'absolute', bottom: 90, opacity: prog(f, 44, 60) }}>
        for MacBooks · macOS 14 or later
      </Mono>
    </AbsoluteFill>
  );
}
