import { Easing, interpolate } from 'remotion';
import { BASE_D, BASE_T } from './three/MacBook';
import { T } from './theme';
import type { ScreenState } from './screen/drawScreen';

const ease = Easing.bezier(0.65, 0, 0.35, 1);
const closeEase = Easing.bezier(0.5, 0, 0.9, 0.6);

export function ramp(f: number, a: number, b: number, from = 0, to = 1, e = ease) {
  return interpolate(f, [a, b], [from, to], { easing: e, extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
}

export const OPEN = 1.9;

export function lidAngle(f: number) {
  if (f < T.close1) return OPEN;
  if (f < T.closed1) return ramp(f, T.close1, T.closed1, OPEN, 0, closeEase);
  if (f < T.reopen) return 0;
  if (f < T.push1) return ramp(f, T.reopen, T.push1, 0, OPEN);
  if (f < T.close2) return OPEN;
  if (f < T.closed2) return ramp(f, T.close2, T.closed2, OPEN, 0, closeEase);
  if (f < T.open3) return 0;
  return ramp(f, T.open3, T.open3 + 34, 0, OPEN);
}

type V3 = [number, number, number];
type Pose = { pos: V3; target: V3 };

const hinge: V3 = [0, BASE_T + 0.012, -BASE_D / 2];
const zc = 0.2 + (3.04 - 0.15) / 1.6 / 2;
const screenCenter: V3 = [0, hinge[1] + zc * Math.sin(OPEN), hinge[2] + zc * Math.cos(OPEN)];
const normal: V3 = [0, -Math.cos(OPEN), Math.sin(OPEN)];
/** Distance at which the 16:10 screen fills the 30 degree frame height. */
export const SCREEN_DIST = (3.04 - 0.15) / 1.6 / 2 / Math.tan((15 * Math.PI) / 180);

const at = (d: number): Pose => ({
  pos: [screenCenter[0] + normal[0] * d, screenCenter[1] + normal[1] * d, screenCenter[2] + normal[2] * d],
  target: screenCenter,
});

const P = {
  hero1: { pos: [4.4, 3.1, 6.2], target: [-0.75, 0.25, -0.2] } as Pose,
  hero1b: { pos: [3.4, 2.8, 6.6], target: [-0.85, 0.3, -0.25] } as Pose,
  screen: at(SCREEN_DIST),
  hero2: { pos: [-3.2, 2.9, 6.4], target: [-0.9, 0.25, -0.1] } as Pose,
  nightA: { pos: [-5.0, 5.9, 5.6], target: [-0.7, 0.35, 0.2] } as Pose,
  nightB: { pos: [5.0, 5.4, 6.2], target: [-0.7, 0.35, 0.2] } as Pose,
  morning: { pos: [0, 1.9, 6.6], target: [0, 0.65, -0.4] } as Pose,
};

const keys: [number, Pose][] = [
  [T.open1, P.hero1],
  [T.push1, P.hero1b],
  [T.flatIn, P.screen],
  [T.flatOut, P.screen],
  [T.close2, P.hero2],
  [T.closed2 + 30, P.nightA],
  [T.nightEnd - 24, P.nightB],
  [T.open3 + 34, P.morning],
  [T.open3 + 104, at(SCREEN_DIST * 1.02)],
];

function lerp(a: V3, b: V3, t: number): V3 {
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
}

export function camera(f: number): Pose {
  if (f <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [fa, a] = keys[i];
    const [fb, b] = keys[i + 1];
    if (f <= fb) {
      // The night orbit drifts at a steady speed; every other move eases.
      const linear = fa === T.closed2 + 30;
      const t = linear ? (f - fa) / (fb - fa) : ramp(f, fa, fb);
      return { pos: lerp(a.pos, b.pos, t), target: lerp(a.target, b.target, t) };
    }
  }
  return keys[keys.length - 1][1];
}

/** 0 = day, 1 = night. */
export function night(f: number) {
  if (f < T.closed2) return 0;
  if (f < T.nightEnd - 60) return ramp(f, T.closed2, T.closed2 + 50);
  return ramp(f, T.nightEnd - 60, T.nightEnd + 10, 1, 0);
}

export function screenState(f: number): ScreenState {
  const morning = f >= T.open3;
  let brightness = 1;
  if (f >= T.close1 && f < T.reopen) brightness = ramp(f, T.close1 + 14, T.closed1 - 4, 1, 0);
  else if (f >= T.reopen && f < T.close2) brightness = ramp(f, T.reopen + 8, T.reopen + 22, 0, 1);
  else if (f >= T.close2 && f < T.open3) brightness = ramp(f, T.close2 + 14, T.closed2 - 4, 1, 0);
  else if (morning) brightness = ramp(f, T.open3 + 6, T.open3 + 24, 0, 1);

  let progress = ramp(f, T.open1, T.close1, 0.05, 0.25, (x) => x);
  if (f >= T.flatOut) progress = ramp(f, T.flatOut, T.close2, 0.25, 0.32, (x) => x);

  return {
    clock: morning ? 'Wed 07:25' : f >= T.close2 ? 'Tue 22:54' : 'Tue 22:53',
    cupOn: f >= T.click,
    progress,
    done: morning,
    brightness,
  };
}
