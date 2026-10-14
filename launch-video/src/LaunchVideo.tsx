import React from 'react';
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame } from 'remotion';
import { easeInOut, prog } from './kit';
import { Caption3D, EndCard, Guardrails, NightHud, Password, Problem, Stats } from './scenes/Cards';
import { FlatClick } from './scenes/FlatClick';
import { Scene3D } from './three/Scene3D';
import { night } from './timeline';
import { color, T } from './theme';

function Fade({ from, to, inDur = 10, outDur = 10, children }: { from: number; to: number; inDur?: number; outDur?: number; children: React.ReactNode }) {
  const f = useCurrentFrame();
  const i = inDur > 0 ? prog(f, from, from + inDur, easeInOut) : 1;
  const o = i * (outDur > 0 ? 1 - prog(f, to - outDur, to, easeInOut) : 1);
  return (
    <Sequence from={from} durationInFrames={to - from}>
      <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>
    </Sequence>
  );
}

function Backdrop() {
  const f = useCurrentFrame();
  const n = night(f);
  const morning = prog(f, T.nightEnd - 40, T.nightEnd + 20) * (1 - prog(f, T.threeEnd - 40, T.threeEnd));
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ background: `radial-gradient(ellipse at 50% 42%, #FFFFFF 0%, ${color.paper} 55%, #EEF2F8 100%)` }} />
      <AbsoluteFill style={{ opacity: morning * (1 - n), background: `radial-gradient(ellipse at 70% 20%, #FFFDF8 0%, ${color.morning} 60%, #F3EEE6 100%)` }} />
      {/* Blue hour under the night on the way down, a sunrise under it on the way up, so no fade passes through grey. */}
      <AbsoluteFill style={{ opacity: f < T.nightEnd - 120 ? Math.min(1, n * 3) : 0, background: 'linear-gradient(180deg, #3D5F9E 0%, #7FA0D6 100%)' }} />
      <AbsoluteFill style={{ opacity: f >= T.nightEnd - 120 ? Math.min(1, n * 3) : 0, background: 'linear-gradient(180deg, #7B78B8 0%, #F0A889 45%, #FFE9D6 100%)' }} />
      <AbsoluteFill style={{ opacity: n, background: `radial-gradient(ellipse at 50% 30%, ${color.nightTop} 0%, ${color.night} 70%)` }} />
    </AbsoluteFill>
  );
}

export const LaunchVideo = () => (
  <AbsoluteFill style={{ background: color.paper }}>
    <Audio src={staticFile('score.wav')} />
    <Backdrop />

    <Fade from={T.open1 - 8} to={T.flatIn + 14} inDur={12} outDur={0}>
      <Scene3D offset={T.open1 - 8} />
      <Caption3D offset={T.open1 - 8} />
    </Fade>

    <Fade from={T.flatIn} to={T.flatOut + 12} inDur={12} outDur={12}>
      <FlatClick />
    </Fade>

    <Fade from={T.flatOut} to={T.threeEnd} inDur={12} outDur={0}>
      <Scene3D offset={T.flatOut} />
      <Caption3D offset={T.flatOut} />
      <NightHud offset={T.flatOut} />
    </Fade>

    <Fade from={0} to={T.open1 + 4} inDur={0} outDur={12}>
      <Problem />
    </Fade>

    <Fade from={T.stats} to={T.guard + 8} inDur={8} outDur={8}>
      <Stats />
    </Fade>
    <Fade from={T.guard} to={T.password + 8} inDur={8} outDur={8}>
      <Guardrails />
    </Fade>
    <Fade from={T.password} to={T.end + 8} inDur={8} outDur={8}>
      <Password />
    </Fade>
    <Fade from={T.end} to={T.total} inDur={10} outDur={0}>
      <EndCard />
    </Fade>
  </AbsoluteFill>
);
