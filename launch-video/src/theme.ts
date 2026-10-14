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
  problemA: 0,
  problemB: 50,
  open1: 104, // 3D starts
  close1: 164,
  closed1: 192,
  reopen: 284,
  push1: 310,
  flatIn: 356, // flat desktop crossfade in
  click: 430,
  flatOut: 524, // back to 3D
  close2: 566,
  closed2: 594,
  nightEnd: 860,
  open3: 860,
  done3: 894,
  threeEnd: 1004,
  stats: 1004,
  guard: 1124,
  password: 1304,
  swap: 1386, // the password card moves to its second half
  end: 1466,
  total: 1601,
};
