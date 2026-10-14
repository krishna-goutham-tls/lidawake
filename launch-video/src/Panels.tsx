import React from 'react';
import { Img, staticFile } from 'remotion';
import { font } from './theme';

// HTML copies of the 0.3.0 panels, in points, so they stay sharp at any zoom.
// Layout values mirror Sources/Panel.swift.

const secondary = 'rgba(60,60,67,0.6)';

function Popover({ children, width, arrow = true }: { children: React.ReactNode; width?: number; arrow?: boolean }) {
  return (
    <div style={{ position: 'relative', width, filter: 'drop-shadow(0 8px 18px rgba(20,40,80,0.16)) drop-shadow(0 0.5px 1.5px rgba(0,0,0,0.18))' }}>
      {arrow && (
        <div style={{ position: 'absolute', left: '50%', top: -5, width: 12, height: 12, marginLeft: -6, background: '#fff', transform: 'rotate(45deg)', borderRadius: 2 }} />
      )}
      <div style={{ position: 'relative', background: '#fff', borderRadius: 10 }}>{children}</div>
    </div>
  );
}

export function FeedbackPanel({ on = true }: { on?: boolean }) {
  return (
    <Popover>
      <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 14px', whiteSpace: 'nowrap' }}>
        <Img src={staticFile(on ? 'cup-on-blue.png' : 'cup-off-ink.png')} style={{ height: 22, opacity: on ? 1 : 0.5 }} />
        <div>
          <div style={{ fontFamily: font.sans, fontSize: 13, fontWeight: 600, color: '#000', letterSpacing: '-0.01em' }}>
            {on ? 'On. Close the lid any time.' : 'Off. Your Mac sleeps normally.'}
          </div>
          {on && (
            <div style={{ fontFamily: font.mono, fontSize: 10.5, color: secondary, marginTop: 2 }}>stops at 20% · 80% now</div>
          )}
        </div>
      </div>
    </Popover>
  );
}

function PillButton({ children, primary }: { children: React.ReactNode; primary?: boolean }) {
  return (
    <div
      style={{
        fontFamily: font.sans,
        fontSize: 13,
        fontWeight: primary ? 500 : 400,
        height: 28,
        padding: '0 15px',
        borderRadius: 14,
        display: 'flex',
        alignItems: 'center',
        color: primary ? '#fff' : '#000',
        background: primary ? '#0A84FF' : 'rgba(0,0,0,0.07)',
      }}
    >
      {children}
    </div>
  );
}

export function SetupPanel() {
  return (
    <Popover width={300}>
      <div style={{ padding: 20, fontFamily: font.sans }}>
        <Img src={staticFile('cup-on-blue.png')} style={{ height: 32, display: 'block', marginBottom: 12, marginLeft: -3 }} />
        <div style={{ fontSize: 17, fontWeight: 600, letterSpacing: '-0.015em', color: '#000' }}>Close the lid. Keep working.</div>
        <div style={{ fontSize: 13, color: secondary, marginTop: 4, lineHeight: 1.3 }}>
          Your Mac stays awake
          <br />
          so your agents can finish.
        </div>
        <div style={{ fontSize: 11.5, color: secondary, marginTop: 18 }}>macOS asks for your password once.</div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 12 }}>
          <PillButton>Not now</PillButton>
          <PillButton primary>Allow once</PillButton>
        </div>
        <div style={{ height: 1, background: 'rgba(0,0,0,0.1)', marginTop: 16 }} />
        <div style={{ fontFamily: font.mono, fontSize: 10.5, color: secondary, marginTop: 10 }}>stops at 20% battery · stops if hot</div>
      </div>
    </Popover>
  );
}
