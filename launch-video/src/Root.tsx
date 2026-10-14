import { Composition } from 'remotion';
import { LaunchVideo } from './LaunchVideo';
import { FPS, H, T, W } from './theme';

export const Root = () => (
  <Composition id="LaunchVideo" component={LaunchVideo} durationInFrames={T.total} fps={FPS} width={W} height={H} />
);
