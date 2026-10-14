import { Composition, Still } from 'remotion';
import { LaunchVideo } from './LaunchVideo';
import { ThumbA, ThumbB, ThumbC } from './Thumbnails';
import { FPS, H, T, W } from './theme';

export const Root = () => (
  <>
    <Composition id="LaunchVideo" component={LaunchVideo} durationInFrames={T.total} fps={FPS} width={W} height={H} />
    <Still id="ThumbA" component={ThumbA} width={W} height={H} />
    <Still id="ThumbB" component={ThumbB} width={W} height={H} />
    <Still id="ThumbC" component={ThumbC} width={W} height={H} />
    {/* GitHub social preview: 2:1, scaled to 1280x640 after render. */}
    <Still id="Social" component={ThumbA} width={W} height={W / 2} />
  </>
);
