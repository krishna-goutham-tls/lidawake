import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from 'remotion';
import { easeInOut, easeOut, Mono, prog, Rise } from '../kit';
import { NIGHT } from '../night-log';
import { SetupPanel } from '../Panels';
import { color, font, T } from '../theme';
import { night } from '../timeline';

const CAPTION = 84;
const CAPTION_W = 1180;

/** Captions laid over the 3D shots. Frame is global. */
export function Caption3D({ offset }: { offset: number }) {
  const f = useCurrentFrame() + offset;
  const local = (a: number) => a - offset;
  const line = (text: string, a: number, b: number) => {
    if (f < a - 2 || f > b + 12) return null;
    // A paper-coloured wash keeps the line readable when the camera pushes into the screen or the keyboard.
    const wash = prog(f, a - 6, a + 6) * (1 - prog(f, b, b + 12)) * (1 - night(f));
    return (
      <AbsoluteFill style={{ justifyContent: 'flex-end', padding: '0 150px 104px' }}>
        <AbsoluteFill style={{ opacity: wash, background: `radial-gradient(ellipse 80% 62% at 0% 100%, rgba(247,249,252,0.97) 0%, rgba(247,249,252,0.9) 45%, rgba(247,249,252,0) 100%)` }} />
        <Rise text={text} at={local(a)} out={local(b)} size={CAPTION} stagger={2} style={{ maxWidth: CAPTION_W, position: 'relative' }} />
      </AbsoluteFill>
    );
  };
  return (
    <>
      {/* Fully on screen from the first frame: a muted feed decides in about two seconds. */}
      {line('When you close the lid, your Mac sleeps and your agent stops.', T.open1 - 40, T.reopen - 6)}
      {line('LidAwake keeps your Mac awake with the lid closed.', T.reopen + 2, T.flatIn + 4)}
      {line('Close the lid, and your agent keeps working.', T.flatOut + 8, T.closed2 + 24)}
    </>
  );
}

/** The night: a real clock, real heartbeats, real battery. Frame is global. */
export function NightHud({ offset }: { offset: number }) {
  const f = useCurrentFrame() + offset;
  const a = T.closed2 + 16;
  const b = T.nightEnd - 70;
  const t = interpolate(f, [a, b], [0, NIGHT.length - 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: easeInOut });
  const i = Math.round(t);
  const [clock, battery] = NIGHT[i];
  // Only on a dark sky, so the white type never sits on the grey middle of the fade.
  const vis = prog(f, T.closed2 + 28, T.closed2 + 42) * (1 - prog(f, T.nightEnd - 58, T.nightEnd - 46));
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
        <Mono size={24} tone="rgba(214,226,255,0.7)" style={{ marginBottom: 14 }}>
          This is the real log from that night.
        </Mono>
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
      <Rise text="The Mac stayed awake all night on battery." at={0} size={104} stagger={2} accent={['awake']} style={{ maxWidth: 1300 }} />
      <Mono size={28} style={{ opacity: prog(f, 14, 28), marginTop: 26 }}>
        one real night, Oct 13 to 14, 2026, MacBook unplugged
      </Mono>
      <div style={{ display: 'flex', gap: 120, marginTop: 72 }}>
        <Stat big="8h 31m" label="with the lid closed" at={20} />
        <Stat big="512" label="heartbeats in the log, one a minute" at={25} />
        <Stat big="12%" label="of the battery used, 80% to 68%" at={30} />
      </div>
      <Mono size={22} style={{ opacity: prog(f, 40, 54), marginTop: 64 }} tone="#9CA3AF">
        from ~/Library/Logs/LidAwake.log
      </Mono>
    </AbsoluteFill>
  );
}

/** The guardrails, in one sentence. */
export function Guardrails() {
  const f = useCurrentFrame();
  const icon = (src: string, at: number) => {
    const p = prog(f, at, at + 16);
    return <Img src={staticFile(src)} style={{ height: 150, opacity: p, transform: `translateX(${(1 - p) * -50}px) scale(${0.9 + 0.1 * p})` }} />;
  };
  return (
    <AbsoluteFill style={{ background: color.paper, flexDirection: 'row', alignItems: 'center', padding: '0 150px', gap: 90 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 50, width: 240 }}>
        {icon('battery-ink.png', 0)}
        {icon('thermo-ink.png', 6)}
      </div>
      <div>
        <Rise text="It lets your Mac sleep at 20% battery, or if it gets too hot." at={3} size={96} stagger={2} style={{ maxWidth: 1200 }} />
        <Mono size={32} style={{ marginTop: 26, opacity: prog(f, 24, 38) }}>
          You can set the battery limit to 10, 20, 30 or 50%.
        </Mono>
      </div>
    </AbsoluteFill>
  );
}

/** Setup, honestly: one password, once. */
export function Password() {
  const f = useCurrentFrame();
  const p = prog(f, 4, 26);
  const leave = prog(f, 50, 58, easeInOut);
  const swap = prog(f, 58, 68, easeInOut);
  return (
    <AbsoluteFill style={{ background: color.paper }}>
      <div style={{ position: 'absolute', left: 150, top: 360, width: 1080 }}>
        <div style={{ opacity: 1 - leave, transform: `translateY(${-leave * 30}px)` }}>
          <Rise text="Setup asks for your password one time." at={2} size={96} stagger={2} />
          <Mono size={32} style={{ marginTop: 24, opacity: prog(f, 16, 30) }}>
            It only lets LidAwake turn lid sleep on and off.
          </Mono>
        </div>
        <div style={{ position: 'absolute', top: 0, opacity: swap, transform: `translateY(${(1 - swap) * 30}px)` }}>
          <Rise text="It needs no account and never goes online." at={60} size={96} stagger={2} />
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          right: 150,
          top: 300,
          transformOrigin: '100% 0',
          opacity: p * (1 - swap * 0.65),
          transform: `scale(${1.5 + 0.05 * p}) translateY(${(1 - p) * 20}px)`,
        }}
      >
        <SetupPanel />
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
        <Rise text="Your agents keep running when you close the lid." at={18} size={54} weight={500} stagger={2} tone={color.mist} style={{ textAlign: 'center' }} />
      </div>
      <Mono size={24} tone="#9CA3AF" style={{ position: 'absolute', bottom: 90, opacity: prog(f, 36, 50) }}>
        for MacBooks on macOS 14 or later
      </Mono>
    </AbsoluteFill>
  );
}
