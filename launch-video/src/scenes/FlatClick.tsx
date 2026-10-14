import { useLayoutEffect, useRef } from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { FeedbackPanel } from '../Panels';
import { CUP, drawScreen, MENU_H, SCREEN_H, SCREEN_IMAGES, SCREEN_W } from '../screen/drawScreen';
import { easeInOut, prog, Rise } from '../kit';
import { screenState } from '../timeline';
import { T } from '../theme';
import { useImagesReady } from '../useImages';

const K = 1080 / SCREEN_H; // screen fitted to frame height
const LEFT = (1920 - SCREEN_W * K) / 2;
const RES = 3; // canvas pixels per screen pixel, so the zoom stays sharp
const CUP0 = { x: LEFT + CUP.x * K, y: CUP.y * K };
const ZOOM = 3.0;
const PT = 1.58 * K; // screen pixels per point, at rest
const CUP_TARGET = { x: 1190, y: 64 };

function Cursor({ pressed }: { pressed: boolean }) {
  return (
    <svg width={64} height={94} viewBox="0 0 17 25" style={{ transform: `scale(${pressed ? 0.88 : 1})`, transformOrigin: '2px 2px' }}>
      <path d="M1 1 L1 19 L5.5 14.8 L8.6 22 L11.6 20.7 L8.6 13.7 L14.6 13.7 Z" fill="#000" stroke="#fff" strokeWidth={1.3} strokeLinejoin="round" />
    </svg>
  );
}

/** The click, flat and close: zoom into the menu bar, click the cup, the real panel drops down. */
export function FlatClick() {
  const local = useCurrentFrame();
  const f = local + T.flatIn;
  const ready = useImagesReady(SCREEN_IMAGES);
  const canvas = useRef<HTMLCanvasElement>(null);
  const state = screenState(f);

  useLayoutEffect(() => {
    if (!ready || !canvas.current) return;
    const ctx = canvas.current.getContext('2d')!;
    ctx.setTransform(RES, 0, 0, RES, 0, 0);
    drawScreen(ctx, state);
  });

  const z = prog(f, T.flatIn + 14, T.click - 30, easeInOut);
  const s = 1 + (ZOOM - 1) * z;
  const cx = CUP0.x + (CUP_TARGET.x - CUP0.x) * z;
  const cy = CUP0.y + (CUP_TARGET.y - CUP0.y) * z;
  const tx = cx - s * CUP0.x;
  const ty = cy - s * CUP0.y;

  // Cursor glides in from the lower left of the zoomed view and lands on the cup.
  const c = prog(f, T.click - 34, T.click - 4, easeInOut);
  const curX = 1560 + (CUP_TARGET.x - 8 - 1560) * c;
  const curY = 820 + (CUP_TARGET.y - 6 - 820) * c;
  const pressed = f >= T.click - 2 && f < T.click + 4;
  const cursorIn = prog(f, T.click - 40, T.click - 30);

  // The app closes this panel after 1.8 s; the video does the same.
  const panelIn = prog(f, T.click + 3, T.click + 15) * (1 - prog(f, T.click + 54, T.click + 62));

  return (
    <AbsoluteFill style={{ background: '#050506', overflow: 'hidden' }}>
      <div style={{ position: 'absolute', left: 0, top: 0, transformOrigin: '0 0', transform: `translate(${tx}px, ${ty}px) scale(${s})` }}>
        <canvas
          ref={canvas}
          width={SCREEN_W * RES}
          height={SCREEN_H * RES}
          style={{ position: 'absolute', left: LEFT, top: 0, width: SCREEN_W * K, height: SCREEN_H * K }}
        />
        {/* The pressed highlight macOS draws behind a menu bar item. */}
        {f >= T.click && f < T.click + 58 && (
          <div
            style={{
              position: 'absolute',
              left: CUP0.x - 17,
              top: 2,
              width: 34,
              height: MENU_H * K - 4,
              borderRadius: 6,
              background: 'rgba(0,0,0,0.10)',
            }}
          />
        )}
        <div
          style={{
            position: 'absolute',
            left: CUP0.x,
            top: MENU_H * K + 6,
            opacity: panelIn,
            transformOrigin: '0 0',
            transform: `scale(${PT * (0.96 + 0.04 * panelIn)}) translate(-50%, ${(1 - panelIn) * -4}px)`,
          }}
        >
          <FeedbackPanel />
        </div>
      </div>

      <div style={{ position: 'absolute', left: curX, top: curY, opacity: cursorIn * (1 - prog(f, T.click + 30, T.click + 44)) }}>
        <Cursor pressed={pressed} />
      </div>

      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: prog(f, T.click - 40, T.click - 20) * (1 - prog(f, T.flatOut - 12, T.flatOut)),
          background: 'linear-gradient(90deg, rgba(247,249,252,1) 0%, rgba(247,249,252,0.97) 36%, rgba(247,249,252,0) 62%)',
        }}
      />
      <div style={{ position: 'absolute', left: 130, top: 480, width: 1000 }}>
        <Rise text="One click turns it on." at={T.click - T.flatIn - 50} out={T.flatOut - T.flatIn - 14} size={160} stagger={4} />
      </div>
      <div style={{ position: 'absolute', left: 136, top: 820, opacity: prog(f, T.click + 16, T.click + 34) }}>
        <Rise text="Click again to turn it off." at={T.click - T.flatIn + 16} out={T.flatOut - T.flatIn - 14} size={56} weight={500} tone="#4B5563" />
      </div>
    </AbsoluteFill>
  );
}

