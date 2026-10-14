import { ThreeCanvas } from '@remotion/three';
import { useThree } from '@react-three/fiber';
import { useEffect, useMemo } from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import * as THREE from 'three';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { drawScreen, SCREEN_H, SCREEN_IMAGES, SCREEN_W, type ScreenState } from '../screen/drawScreen';
import { useImagesReady } from '../useImages';
import { camera, lidAngle, night, screenState } from '../timeline';
import { MacBook } from './MacBook';

function Environment() {
  const { gl, scene } = useThree();
  // Set during render, not in an effect: a metal with no environment renders black on the first frame.
  const env = useMemo(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const texture = pmrem.fromScene(new RoomEnvironment(), 0.03).texture;
    pmrem.dispose();
    return texture;
  }, [gl]);
  scene.environment = env;
  useEffect(() => () => env.dispose(), [env]);
  return null;
}

export type Pose = ReturnType<typeof camera>;

/** Everything one frame of the 3D shot depends on. */
export type Shot = { pose: Pose; lid: number; n: number; screen: ScreenState };

export function shotAt(f: number): Shot {
  return { pose: camera(f), lid: lidAngle(f), n: night(f), screen: screenState(f) };
}

function CameraRig({ pose }: { pose: Pose }) {
  const { camera: cam } = useThree();
  cam.position.set(...pose.pos);
  cam.lookAt(...pose.target);
  cam.updateProjectionMatrix();
  return null;
}

function Shadow({ strength }: { strength: number }) {
  const tex = useMemo(() => {
    const c = document.createElement('canvas');
    c.width = 256;
    c.height = 256;
    const ctx = c.getContext('2d')!;
    const g = ctx.createRadialGradient(128, 128, 10, 128, 128, 128);
    g.addColorStop(0, 'rgba(0,0,0,0.55)');
    g.addColorStop(0.55, 'rgba(0,0,0,0.22)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 256, 256);
    return new THREE.CanvasTexture(c);
  }, []);
  return (
    <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, -0.002, -0.05]}>
      <planeGeometry args={[4.6, 3.6]} />
      <meshBasicMaterial map={tex} transparent opacity={strength} depthWrite={false} />
    </mesh>
  );
}

function World({ shot }: { shot: Shot }) {
  const { n } = shot;
  const { canvas, texture } = useMemo(() => {
    const c = document.createElement('canvas');
    c.width = SCREEN_W;
    c.height = SCREEN_H;
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return { canvas: c, texture: t };
  }, []);

  const ctx = canvas.getContext('2d')!;
  drawScreen(ctx, shot.screen);
  texture.needsUpdate = true;

  const key = new THREE.Color('#FFFFFF').lerp(new THREE.Color('#7FA4FF'), n);
  return (
    <>
      <Environment />
      <CameraRig pose={shot.pose} />
      <ambientLight intensity={0.35 - 0.25 * n} />
      <directionalLight position={[3, 6, 4]} intensity={2.2 - 1.6 * n} color={key} />
      <directionalLight position={[-5, 2, -3]} intensity={0.6 + 1.4 * n} color={n > 0.5 ? '#6E8FFF' : '#FFFFFF'} />
      <MacBook lidAngle={shot.lid} screen={texture} />
      <Shadow strength={0.55 - 0.25 * n} />
    </>
  );
}

/** Frames are absolute so a scene mounted in a Sequence keeps the global timeline. */
export function Scene3D({ offset }: { offset: number }) {
  const local = useCurrentFrame();
  return <Scene3DShot shot={shotAt(local + offset)} />;
}

export function Scene3DShot({ shot, fov = 30 }: { shot: Shot; fov?: number }) {
  const { width, height } = useVideoConfig();
  const { n } = shot;
  const ready = useImagesReady(SCREEN_IMAGES);
  if (!ready) return null;
  return (
    <ThreeCanvas
      width={width}
      height={height}
      camera={{ fov, near: 0.1, far: 100 }}
      gl={{ antialias: true, alpha: true, preserveDrawingBuffer: true }}
      onCreated={({ gl, scene }) => {
        gl.toneMapping = THREE.ACESFilmicToneMapping;
        gl.toneMappingExposure = 1.0;
        scene.background = null;
      }}
      style={{ position: 'absolute', inset: 0, opacity: 1 }}
    >
      <group>
        <World shot={shot} />
      </group>
      {/* Exposure follows the evening-to-night move. */}
      <ExposureRig n={n} />
    </ThreeCanvas>
  );
}

function ExposureRig({ n }: { n: number }) {
  const { gl, scene } = useThree();
  gl.toneMappingExposure = 1.0 - 0.35 * n;
  scene.environmentIntensity = 1 - 0.75 * n;
  return null;
}
