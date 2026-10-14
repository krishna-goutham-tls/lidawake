import { staticFile } from 'remotion';
import { font } from '../theme';

export const SCREEN_W = 1920;
export const SCREEN_H = 1200;
export const MENU_H = 38;
/** Where the cup sits in the menu bar, in screen pixels. The flat scene anchors the panel here. */
export const CUP = { x: 1556, y: MENU_H / 2 };

export type ScreenState = {
  clock: string;
  cupOn: boolean;
  /** 0..1, how far the agent has got. */
  progress: number;
  done: boolean;
  /** 0 = black (asleep or off), 1 = full. */
  brightness: number;
};

const images = new Map<string, HTMLImageElement>();
export function preloadImage(name: string): HTMLImageElement {
  let img = images.get(name);
  if (!img) {
    img = new Image();
    img.src = staticFile(name);
    images.set(name, img);
  }
  return img;
}

export const SCREEN_IMAGES = ['cup-on-ink.png', 'cup-off-ink.png', 'wifi-ink.png', 'battery75-ink.png'];

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

const STEPS = [
  'Update the payments client',
  'Rewrite the checkout handlers',
  'Migrate the webhooks',
  'Move refunds to the new endpoints',
  'Update the fixtures',
  'Run the full test suite',
  'Fix the failing tests',
  'Run the full test suite again',
  'Write the summary',
];

type Line = { text: string; color: string; bold?: boolean };

function agentLines(progress: number, done: boolean): Line[] {
  const dim = '#8B93A1';
  const fg = '#E6E9EF';
  const accent = '#7FB2FF';
  const ok = '#5ED3A6';
  const lines: Line[] = [
    { text: '~/payments-app $ claude', color: fg },
    { text: '', color: fg },
    { text: '> Move checkout to the new payments API. Run the full', color: accent },
    { text: '  test suite and fix anything that breaks.', color: accent },
    { text: '', color: fg },
    { text: '● Read 214 files', color: dim },
    { text: '● Plan: 9 steps', color: dim },
  ];
  const shown = done ? STEPS.length : Math.min(STEPS.length - 1, Math.floor(progress * (STEPS.length - 1)) + 1);
  for (let i = 0; i < shown; i++) {
    const finished = done || i < shown - 1;
    lines.push({
      text: `${finished ? '✓' : '◐'} ${i + 1}/9  ${STEPS[i]}${finished ? '' : '…'}`,
      color: finished ? fg : accent,
    });
  }
  if (done) {
    lines.push({ text: '', color: fg });
    lines.push({ text: '✓ All tests pass. 41 files changed.', color: ok, bold: true });
    lines.push({ text: '✓ Done. Summary in SUMMARY.md', color: ok, bold: true });
  }
  return lines;
}

export function drawScreen(ctx: CanvasRenderingContext2D, s: ScreenState) {
  const w = SCREEN_W;
  const h = SCREEN_H;
  ctx.save();
  ctx.clearRect(0, 0, w, h);

  // Wallpaper: calm blue, a soft wash of mint at the bottom.
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, '#BCD5F7');
  g.addColorStop(0.55, '#DCE8F8');
  g.addColorStop(1, '#E3F2EC');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  const r = ctx.createRadialGradient(w * 0.78, h * 0.25, 0, w * 0.78, h * 0.25, w * 0.5);
  r.addColorStop(0, 'rgba(255,255,255,0.65)');
  r.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = r;
  ctx.fillRect(0, 0, w, h);

  // Terminal window.
  const tx = 110, ty = 110, tw = 1010, th = 960;
  ctx.save();
  ctx.shadowColor = 'rgba(20,40,80,0.35)';
  ctx.shadowBlur = 60;
  ctx.shadowOffsetY = 24;
  roundRect(ctx, tx, ty, tw, th, 18);
  ctx.fillStyle = '#16181D';
  ctx.fill();
  ctx.restore();
  roundRect(ctx, tx, ty, tw, th, 18);
  ctx.strokeStyle = 'rgba(255,255,255,0.10)';
  ctx.lineWidth = 2;
  ctx.stroke();

  // Title bar with three tabs.
  ctx.fillStyle = '#1F2228';
  ctx.save();
  roundRect(ctx, tx, ty, tw, 58, 18);
  ctx.clip();
  ctx.fillRect(tx, ty, tw, 58);
  ctx.restore();
  ['#FF5F57', '#FEBC2E', '#28C840'].forEach((c, i) => {
    ctx.beginPath();
    ctx.arc(tx + 30 + i * 26, ty + 29, 8, 0, Math.PI * 2);
    ctx.fillStyle = c;
    ctx.fill();
  });
  const tabs = ['claude', 'codex', 'droid'];
  tabs.forEach((t, i) => {
    const x = tx + 130 + i * 186;
    if (i === 0) {
      roundRect(ctx, x, ty + 12, 176, 36, 8);
      ctx.fillStyle = '#2B2F37';
      ctx.fill();
    }
    ctx.font = `500 21px ${font.sans}`;
    ctx.fillStyle = i === 0 ? '#E6E9EF' : '#7D8594';
    ctx.textAlign = 'center';
    ctx.fillText(t, x + 88, ty + 37);
  });
  ctx.textAlign = 'left';

  // Agent output.
  const lines = agentLines(s.progress, s.done);
  const lh = 38;
  let y = ty + 112;
  for (const line of lines) {
    ctx.font = `${line.bold ? 700 : 400} 26px ${font.mono}`;
    ctx.fillStyle = line.color;
    ctx.fillText(line.text, tx + 40, y);
    y += lh;
  }
  if (!s.done) {
    // Block cursor.
    ctx.fillStyle = 'rgba(230,233,239,0.85)';
    ctx.fillRect(tx + 40, y - 26, 14, 30);
  }

  // Menu bar.
  ctx.fillStyle = 'rgba(246,248,252,0.82)';
  ctx.fillRect(0, 0, w, MENU_H);
  ctx.fillStyle = '#16181D';
  ctx.font = `700 20px ${font.sans}`;
  ctx.fillText('Terminal', 34, 26);
  ctx.font = `400 20px ${font.sans}`;
  let mx = 140;
  for (const m of ['Shell', 'Edit', 'View', 'Window', 'Help']) {
    ctx.fillText(m, mx, 26);
    mx += ctx.measureText(m).width + 30;
  }
  // Right side: cup, wifi, battery, clock.
  const cup = preloadImage(s.cupOn ? 'cup-on-ink.png' : 'cup-off-ink.png');
  if (cup.complete && cup.naturalWidth) {
    const ch = 30;
    const cw = (cup.naturalWidth / cup.naturalHeight) * ch;
    ctx.drawImage(cup, CUP.x - cw / 2, CUP.y - ch / 2 - 1, cw, ch);
  }
  const wifi = preloadImage('wifi-ink.png');
  if (wifi.complete && wifi.naturalWidth) ctx.drawImage(wifi, 1600, 6, 30, 26);
  const bat = preloadImage('battery75-ink.png');
  if (bat.complete && bat.naturalWidth) ctx.drawImage(bat, 1648, 7, 44, 24);
  ctx.font = `500 20px ${font.sans}`;
  ctx.textAlign = 'right';
  ctx.fillText(s.clock, w - 30, 26);
  ctx.textAlign = 'left';

  // Notch.
  ctx.fillStyle = '#000';
  roundRect(ctx, w / 2 - 110, -20, 220, 20 + MENU_H + 4, 14);
  ctx.fill();

  // Sleep or lid fade.
  if (s.brightness < 1) {
    ctx.fillStyle = `rgba(0,0,0,${1 - s.brightness})`;
    ctx.fillRect(0, 0, w, h);
  }
  ctx.restore();
}
