import React from 'react';
import { Easing, interpolate, useCurrentFrame } from 'remotion';
import { color, font } from './theme';

export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

export function clamp01(v: number) {
  return Math.max(0, Math.min(1, v));
}

export function prog(f: number, a: number, b: number, e = easeOut) {
  return interpolate(f, [a, b], [0, 1], { easing: e, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
}

/** Words rise and sharpen one after another. `at` is the local frame the first word starts. */
export function Rise({
  text,
  at = 0,
  stagger = 3,
  size = 120,
  weight = 700,
  tone = color.ink,
  out,
  style,
  accent,
}: {
  text: string;
  at?: number;
  stagger?: number;
  size?: number;
  weight?: number;
  tone?: string;
  /** Local frame at which the line leaves. */
  out?: number;
  style?: React.CSSProperties;
  /** Words to paint in the accent blue. */
  accent?: string[];
}) {
  const f = useCurrentFrame();
  const words = text.split(' ');
  const leave = out === undefined ? 0 : prog(f, out, out + 10, easeInOut);
  return (
    <div
      style={{
        fontFamily: font.sans,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: '-0.045em',
        lineHeight: 1.02,
        color: tone,
        opacity: 1 - leave,
        transform: `translateY(${-leave * 24}px)`,
        ...style,
      }}
    >
      {words.map((w, i) => {
        const p = prog(f, at + i * stagger, at + i * stagger + 16);
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              marginRight: '0.24em',
              opacity: p,
              transform: `translateY(${(1 - p) * 0.35 * size}px)`,
              filter: `blur(${(1 - p) * 10}px)`,
              color: accent?.includes(w.replace(/[.,]/g, '')) ? color.blue : undefined,
            }}
          >
            {w}
          </span>
        );
      })}
    </div>
  );
}

export function Mono({ children, size = 26, tone = color.mist, style }: { children: React.ReactNode; size?: number; tone?: string; style?: React.CSSProperties }) {
  return (
    <div style={{ fontFamily: font.mono, fontSize: size, color: tone, letterSpacing: '0', ...style }}>{children}</div>
  );
}

/** Fades a whole layer in and out on the global timeline. */
export function useLayerOpacity(f: number, inA: number, inB: number, outA?: number, outB?: number) {
  const i = prog(f, inA, inB, easeInOut);
  const o = outA === undefined || outB === undefined ? 0 : prog(f, outA, outB, easeInOut);
  return i * (1 - o);
}
