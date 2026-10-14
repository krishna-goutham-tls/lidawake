export const FPS = 30;
export const W = 1920;
export const H = 1080;

export const color = {
  paper: '#F7F9FC',
  ink: '#12151B',
  mist: '#6B7280',
  blue: '#2E72ED',
  sky: '#DCE9FB',
  mint: '#2FAE85',
  night: '#070D1A',
  nightTop: '#0E1A33',
  morning: '#FBF7F1',
};

export const font = {
  sans: 'system-ui, -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif',
  mono: 'ui-monospace, "SF Mono", Menlo, monospace',
};

/** Shot boundaries in frames. Everything else reads from here. */
// tools/score.py parses this block, so keep one `name: number,` per line.
export const T = {
  open1: 0, // 3D from the first frame
  close1: 66,
  closed1: 94,
  reopen: 140,
  push1: 166,
  flatIn: 200, // flat desktop crossfade in
  click: 270,
  flatOut: 336, // back to 3D
  close2: 366,
  closed2: 394,
  nightEnd: 604,
  open3: 604,
  done3: 638,
  threeEnd: 714,
  stats: 714,
  guard: 814,
  password: 914,
  end: 1024,
  total: 1124,
};
