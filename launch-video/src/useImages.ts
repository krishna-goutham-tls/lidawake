import { useEffect, useState } from 'react';
import { continueRender, delayRender } from 'remotion';
import { preloadImage } from './screen/drawScreen';

/** Holds the frame until every canvas image has decoded, then re-renders so canvases redraw with them. */
export function useImagesReady(names: string[]) {
  const [ready, setReady] = useState(false);
  const [handle] = useState(() => delayRender('canvas images'));
  useEffect(() => {
    Promise.all(
      names.map(
        (n) =>
          new Promise<void>((resolve) => {
            const img = preloadImage(n);
            if (img.complete && img.naturalWidth) return resolve();
            // Several scenes can wait on the same image at once, so never overwrite a handler.
            img.addEventListener('load', () => resolve(), { once: true });
            img.addEventListener('error', () => resolve(), { once: true });
          }),
      ),
    ).then(() => {
      setReady(true);
      continueRender(handle);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return ready;
}
