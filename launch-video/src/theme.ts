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
export const T = {
  problemA: 0,
  problemB: 48,
  open1: 96, // 3D starts
  close1: 156,
  closed1: 184,
  reopen: 246,
  push1: 272,
  flatIn: 318, // flat desktop crossfade in
  click: 392,
  flatOut: 486, // back to 3D
  close2: 528,
  closed2: 556,
  nightEnd: 822,
  open3: 822,
  done3: 856,
  threeEnd: 966,
  stats: 966,
  guard: 1086,
  password: 1266,
  end: 1386,
  total: 1536,
};
