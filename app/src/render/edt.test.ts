import { describe, expect, it } from 'vitest';
import { signedDistanceTransform, signedDistanceTransformAA } from './edt';

describe('signedDistanceTransform', () => {
  // 7×7 grid with a 3×3 filled square centered at (3,3).
  const W = 7;
  const H = 7;
  const mask = new Uint8Array(W * H);
  for (let y = 2; y <= 4; y++) for (let x = 2; x <= 4; x++) mask[y * W + x] = 1;
  const sdf = signedDistanceTransform(mask, W, H);
  const at = (x: number, y: number) => sdf[y * W + x];

  it('is positive inside and negative outside', () => {
    expect(at(3, 3)).toBeGreaterThan(0); // center
    expect(at(0, 0)).toBeLessThan(0); // far corner
  });

  it('grows toward the shape center', () => {
    expect(at(3, 3)).toBeGreaterThan(at(2, 2)); // center deeper than inner corner
  });

  it('measures exact outside distance', () => {
    // (5,3) is one cell right of the filled column x=4 → distance 1.
    expect(at(5, 3)).toBeCloseTo(-1, 5);
    // (6,3) is two cells out → distance 2.
    expect(at(6, 3)).toBeCloseTo(-2, 5);
  });
});

describe('signedDistanceTransformAA', () => {
  it('reduces to the binary transform for 0/1 coverage', () => {
    const W = 7;
    const H = 7;
    const mask = new Uint8Array(W * H);
    const cov = new Float32Array(W * H);
    for (let y = 2; y <= 4; y++)
      for (let x = 2; x <= 4; x++) {
        mask[y * W + x] = 1;
        cov[y * W + x] = 1;
      }
    const a = signedDistanceTransform(mask, W, H);
    const b = signedDistanceTransformAA(cov, W, H);
    for (let i = 0; i < W * H; i++) expect(b[i]).toBeCloseTo(a[i], 5);
  });

  it('places the boundary sub-pixel from fractional coverage', () => {
    // 1×5 row, edge ramp: cell 2 is 75% covered → its center sits 0.25px inside.
    const cov = new Float32Array([0, 0, 0.75, 1, 1]);
    const sdf = signedDistanceTransformAA(cov, 5, 1);
    expect(sdf[2]).toBeCloseTo(0.25, 3);
    expect(sdf[1]).toBeLessThan(0);
    expect(sdf[3]).toBeGreaterThan(0);
  });

  it('a quarter-covered edge cell reads slightly outside', () => {
    const cov = new Float32Array([0, 0, 0.25, 1, 1]);
    const sdf = signedDistanceTransformAA(cov, 5, 1);
    expect(sdf[2]).toBeCloseTo(-0.25, 3);
  });

  it('a half-covered cell sits exactly on the boundary', () => {
    const cov = new Float32Array([0, 0.5, 1]);
    const sdf = signedDistanceTransformAA(cov, 3, 1);
    expect(sdf[1]).toBeCloseTo(0, 5);
  });
});
