import { useMemo } from 'react';
import * as THREE from 'three';

// Proportions of a 13-inch MacBook Air, in decimetres.
export const BASE_W = 3.04;
export const BASE_D = 2.15;
export const BASE_T = 0.105;
export const LID_T = 0.045;
const PLAN_R = 0.17;

function roundedRectShape(w: number, d: number, r: number) {
  const s = new THREE.Shape();
  const x = -w / 2;
  const y = -d / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y);
  s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + d - r);
  s.quadraticCurveTo(x + w, y + d, x + w - r, y + d);
  s.lineTo(x + r, y + d);
  s.quadraticCurveTo(x, y + d, x, y + d - r);
  s.lineTo(x, y + r);
  s.quadraticCurveTo(x, y, x + r, y);
  return s;
}

/** A slab with rounded corners in plan and softened edges, lying flat, bottom at y = 0. */
function slab(w: number, d: number, t: number, r: number, bevel: number) {
  const g = new THREE.ExtrudeGeometry(roundedRectShape(w - bevel * 2, d - bevel * 2, r - bevel), {
    depth: t - bevel * 2,
    bevelEnabled: true,
    bevelSize: bevel,
    bevelThickness: bevel,
    bevelSegments: 6,
    curveSegments: 28,
  });
  g.rotateX(-Math.PI / 2);
  g.translate(0, bevel, 0);
  g.computeVertexNormals();
  return g;
}

function flatRounded(w: number, d: number, r: number) {
  const g = new THREE.ShapeGeometry(roundedRectShape(w, d, r), 24);
  g.rotateX(-Math.PI / 2);
  return g;
}

type KeySpec = { x: number; z: number; w: number; d: number };

function keyboardLayout(): KeySpec[] {
  const total = 2.62;
  const units = 14.5;
  const u = total / units;
  const gap = 0.024;
  const rows: { h: number; keys: number[] }[] = [
    { h: 0.55, keys: Array(14).fill(units / 14) },
    { h: 1, keys: [...Array(13).fill(1), 1.5] },
    { h: 1, keys: [1.5, ...Array(13).fill(1)] },
    { h: 1, keys: [1.75, ...Array(11).fill(1), 1.75] },
    { h: 1, keys: [2.25, ...Array(10).fill(1), 2.25] },
    { h: 1, keys: [1, 1, 1, 1.25, 5, 1.25, 1, 3] },
  ];
  const specs: KeySpec[] = [];
  let z = -BASE_D / 2 + 0.2;
  for (const row of rows) {
    const rowD = row.h * u;
    let x = -total / 2;
    for (const k of row.keys) {
      const kw = k * u;
      specs.push({ x: x + kw / 2, z: z + rowD / 2, w: kw - gap, d: rowD - gap });
      x += kw;
    }
    z += rowD;
  }
  return specs;
}

export function useMacMaterials() {
  return useMemo(() => {
    const aluminium = new THREE.MeshPhysicalMaterial({
      color: '#D3D6DB',
      metalness: 1,
      roughness: 0.34,
      clearcoat: 0.15,
      clearcoatRoughness: 0.4,
    });
    const trackpad = new THREE.MeshPhysicalMaterial({ color: '#CDD0D5', metalness: 1, roughness: 0.22 });
    const groove = new THREE.MeshStandardMaterial({ color: '#8D9096', metalness: 0.6, roughness: 0.5 });
    const key = new THREE.MeshStandardMaterial({ color: '#141518', metalness: 0.1, roughness: 0.62 });
    const well = new THREE.MeshStandardMaterial({ color: '#5E6166', metalness: 0.7, roughness: 0.55 });
    const bezel = new THREE.MeshPhysicalMaterial({ color: '#050506', metalness: 0.2, roughness: 0.12, clearcoat: 1 });
    const hinge = new THREE.MeshStandardMaterial({ color: '#2A2C30', metalness: 0.8, roughness: 0.4 });
    return { aluminium, trackpad, groove, key, well, bezel, hinge };
  }, []);
}

export function MacBook({ lidAngle, screen }: { lidAngle: number; screen: THREE.Texture }) {
  const m = useMacMaterials();
  const geo = useMemo(() => {
    const base = slab(BASE_W, BASE_D, BASE_T, PLAN_R, 0.022);
    const lid = slab(BASE_W, BASE_D, LID_T, PLAN_R, 0.014);
    lid.translate(0, 0, BASE_D / 2);
    const keys = keyboardLayout();
    const keyGeo = new THREE.BoxGeometry(1, 0.012, 1);
    const trackpad = flatRounded(1.34, 0.86, 0.05);
    const trackGroove = flatRounded(1.355, 0.875, 0.055);
    const well = flatRounded(2.66, 1.08, 0.04);
    const bezel = new THREE.ShapeGeometry(roundedRectShape(BASE_W - 0.03, BASE_D - 0.03, PLAN_R - 0.015), 24);
    bezel.rotateX(Math.PI / 2);
    bezel.translate(0, -0.0012, BASE_D / 2);
    const screenW = BASE_W - 0.15;
    const screenH = screenW / 1.6;
    const screenGeo = new THREE.PlaneGeometry(screenW, screenH);
    screenGeo.rotateX(Math.PI / 2);
    screenGeo.translate(0, -0.0024, 0.2 + screenH / 2);
    const hingeGeo = new THREE.CylinderGeometry(0.032, 0.032, BASE_W - 0.5, 24);
    hingeGeo.rotateZ(Math.PI / 2);
    return { base, lid, keys, keyGeo, trackpad, trackGroove, well, bezel, screenGeo, hingeGeo };
  }, []);

  const keyMatrices = useMemo(() => {
    const dummy = new THREE.Object3D();
    return geo.keys.map((k) => {
      dummy.position.set(k.x, BASE_T + 0.004, k.z);
      dummy.scale.set(k.w, 1, k.d);
      dummy.updateMatrix();
      return dummy.matrix.clone();
    });
  }, [geo.keys]);

  const screenMat = useMemo(
    () => new THREE.MeshBasicMaterial({ map: screen, toneMapped: false }),
    [screen],
  );

  return (
    <group>
      <mesh geometry={geo.base} material={m.aluminium} />
      <mesh geometry={geo.well} material={m.well} position={[0, BASE_T + 0.0008, -BASE_D / 2 + 0.2 + 0.52]} />
      <instancedMesh
        args={[geo.keyGeo, m.key, keyMatrices.length]}
        ref={(mesh) => {
          if (!mesh) return;
          keyMatrices.forEach((mat, i) => mesh.setMatrixAt(i, mat));
          mesh.instanceMatrix.needsUpdate = true;
        }}
      />
      <mesh geometry={geo.trackGroove} material={m.groove} position={[0, BASE_T + 0.0006, BASE_D / 2 - 0.13 - 0.43]} />
      <mesh geometry={geo.trackpad} material={m.trackpad} position={[0, BASE_T + 0.0012, BASE_D / 2 - 0.13 - 0.43]} />
      <mesh geometry={geo.hingeGeo} material={m.hinge} position={[0, BASE_T * 0.75, -BASE_D / 2 + 0.035]} />

      <group position={[0, BASE_T + 0.012, -BASE_D / 2]} rotation={[-lidAngle, 0, 0]}>
        <mesh geometry={geo.lid} material={m.aluminium} />
        <mesh geometry={geo.bezel} material={m.bezel} />
        <mesh geometry={geo.screenGeo} material={screenMat} />
      </group>
    </group>
  );
}
