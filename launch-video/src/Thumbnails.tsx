import React from 'react';
import { AbsoluteFill, Img, staticFile } from 'remotion';
import { NIGHT } from './night-log';
import { Scene3DShot, type Shot } from './three/Scene3D';
import { color, font } from './theme';

// Feed rules: keep words out of the centre (play button) and the bottom-left corner (X duration badge).

const NIGHT_BLUE = '#6FA8FF';

function Headline({ lines, size, tone, accentTone, accentFrom, style }: {
  lines: string[];
  size: number;
  tone: string;
  accentTone: string;
  /** Lines from this index on take the accent colour. */
  accentFrom: number;
  style?: React.CSSProperties;
}) {
  return (
    <div style={{ fontFamily: font.sans, fontWeight: 800, fontSize: size, letterSpacing: '-0.04em', wordSpacing: '0.04em', lineHeight: 0.98, ...style }}>
      {lines.map((l, i) => (
        <div key={i} style={{ color: i >= accentFrom ? accentTone : tone, whiteSpace: 'nowrap' }}>{l}</div>
      ))}
    </div>
  );
}

function Brand({ dark, style }: { dark: boolean; style?: React.CSSProperties }) {
  return (
    <div style={{ position: 'absolute', display: 'flex', alignItems: 'center', gap: 18, ...style }}>
      <Img src={staticFile('appicon.png')} style={{ height: 84, filter: 'drop-shadow(0 10px 24px rgba(0,0,0,0.25))' }} />
      <div style={{ fontFamily: font.sans, fontWeight: 700, fontSize: 52, letterSpacing: '-0.03em', color: dark ? '#fff' : color.ink }}>
        LidAwake
      </div>
    </div>
  );
}

const nightSky = `radial-gradient(ellipse at 68% 40%, #1A2B52 0%, ${color.nightTop} 38%, ${color.night} 80%)`;

/** A: the lid is shut and the work goes on. */
export function ThumbA() {
  const shot: Shot = {
    pose: { pos: [3.4, 2.1, 5.2], target: [-1.25, 0.55, -0.4] },
    lid: 0,
    n: 1,
    screen: { clock: 'Wed 03:04', cupOn: true, progress: 0.6, done: false, brightness: 0 },
  };
  const row = (mark: string, markTone: string, text: string, tone: string) => (
    <div style={{ display: 'flex', gap: 22, whiteSpace: 'nowrap' }}>
      <span style={{ color: markTone }}>{mark}</span>
      <span style={{ color: tone }}>{text}</span>
    </div>
  );
  return (
    <AbsoluteFill style={{ background: nightSky }}>
      <Scene3DShot shot={shot} />
      {/* Light pooled on the lid under the card, and a callout tying the card to this laptop. */}
      <div style={{ position: 'absolute', left: 1010, top: 640, width: 720, height: 220, borderRadius: '50%', background: 'radial-gradient(ellipse, rgba(110,165,255,0.38) 0%, rgba(110,165,255,0) 70%)', mixBlendMode: 'screen' }} />
      <div style={{ position: 'absolute', left: 1429, top: 372, width: 2, height: 376, background: 'linear-gradient(180deg, rgba(140,175,255,0.6), rgba(140,175,255,0.15))' }} />
      <div style={{ position: 'absolute', left: 1420, top: 740, width: 20, height: 20, borderRadius: 10, background: NIGHT_BLUE, boxShadow: `0 0 24px ${NIGHT_BLUE}, 0 0 60px rgba(110,165,255,0.6)` }} />
      <Headline
        lines={['Lid closed.', 'Still coding.']}
        size={176}
        tone="#FFFFFF"
        accentTone={NIGHT_BLUE}
        accentFrom={1}
        style={{ position: 'absolute', left: 110, top: 96 }}
      />
      <div
        style={{
          position: 'absolute',
          right: 110,
          top: 96,
          width: 690,
          padding: '30px 36px',
          borderRadius: 26,
          background: 'rgba(14,20,34,0.78)',
          border: '1.5px solid rgba(140,175,255,0.28)',
          boxShadow: '0 30px 80px rgba(0,0,0,0.5), 0 0 60px rgba(80,140,255,0.18)',
          fontFamily: font.mono,
          fontSize: 30,
          lineHeight: '50px',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: '#E6E9EF', marginBottom: 6 }}>
          <span style={{ width: 16, height: 16, borderRadius: 8, background: '#5ED3A6', boxShadow: '0 0 14px #5ED3A6' }} />
          <span style={{ fontWeight: 700 }}>claude</span>
          <span style={{ color: '#8B93A1' }}>running</span>
        </div>
        {row('✓', '#5ED3A6', '5/9 Move refunds', '#C9CFDA')}
        {row('◐', NIGHT_BLUE, '6/9 Update the fixtures…', '#FFFFFF')}
        <div style={{ color: '#8B93A1', fontSize: 25, marginTop: 8 }}>03:04 · lid closed · battery 72%</div>
      </div>
      <Brand dark style={{ left: 116, top: 560 }} />
    </AbsoluteFill>
  );
}

/** B: the real log of the night is the proof. */
export function ThumbB() {
  const first = NIGHT[0];
  const second = NIGHT[1];
  const last = NIGHT[NIGHT.length - 1];
  const line = (t: string, bat: number, strong: boolean) => (
    <div style={{ whiteSpace: 'pre', color: strong ? '#E6E9EF' : '#8B93A1' }}>
      <span style={{ color: strong ? NIGHT_BLUE : '#5C6676' }}>{t}</span>
      {'  heartbeat  lid=closed  battery='}
      <span style={{ color: strong ? '#FFFFFF' : undefined }}>{bat}%</span>
    </div>
  );
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 30% 20%, #18233C 0%, #0B1020 60%, #070A13 100%)` }}>
      <Headline
        lines={['Lid closed 8h 31m.', 'Never slept.']}
        size={156}
        tone="#FFFFFF"
        accentTone={NIGHT_BLUE}
        accentFrom={1}
        style={{ position: 'absolute', left: 110, top: 92 }}
      />
      <div
        style={{
          position: 'absolute',
          left: 110,
          right: 110,
          top: 500,
          borderRadius: 24,
          background: 'rgba(10,14,24,0.9)',
          border: '1.5px solid rgba(140,175,255,0.22)',
          boxShadow: '0 30px 80px rgba(0,0,0,0.55)',
          overflow: 'hidden',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 28px', height: 58, background: 'rgba(255,255,255,0.04)' }}>
          {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
            <span key={c} style={{ width: 16, height: 16, borderRadius: 8, background: c }} />
          ))}
          <span style={{ fontFamily: font.mono, fontSize: 24, color: '#8B93A1', marginLeft: 18 }}>~/Library/Logs/LidAwake.log</span>
        </div>
        <div style={{ padding: '26px 40px 32px', fontFamily: font.mono, fontSize: 44, lineHeight: '68px' }}>
          {line(first[0], first[1], true)}
          {line(second[0], second[1], false)}
          <div style={{ color: '#5C6676', whiteSpace: 'pre' }}>{'  ⋮    509 more, one a minute'}</div>
          {line(last[0], last[1], true)}
        </div>
      </div>
      <div style={{ position: 'absolute', right: 110, top: 128, display: 'flex', alignItems: 'center', gap: 16 }}>
        <Img src={staticFile('appicon.png')} style={{ height: 76 }} />
        <div style={{ fontFamily: font.sans, fontWeight: 700, fontSize: 46, letterSpacing: '-0.03em', color: '#fff' }}>LidAwake</div>
      </div>
    </AbsoluteFill>
  );
}

/** C: the pain, then the fix, in daylight. */
export function ThumbC() {
  const shot: Shot = {
    pose: { pos: [4.6, 2.3, 5.6], target: [-2.35, 0.7, -0.35] },
    lid: 0.62,
    n: 0,
    screen: { clock: 'Tue 22:54', cupOn: false, progress: 0.32, done: false, brightness: 1 },
  };
  return (
    <AbsoluteFill style={{ background: `radial-gradient(ellipse at 70% 45%, #FFFFFF 0%, ${color.paper} 50%, #E6EDF7 100%)` }}>
      <Scene3DShot shot={shot} />
      <Headline
        lines={['Close the lid,', 'your agent stops.', 'Not anymore.']}
        size={132}
        tone={color.ink}
        accentTone={color.blue}
        accentFrom={2}
        style={{ position: 'absolute', left: 110, top: 96 }}
      />
      <Brand dark={false} style={{ left: 116, top: 600 }} />
    </AbsoluteFill>
  );
}
