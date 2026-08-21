import { describe, expect, it } from 'vitest';
import { signedDistanceTransform, signedDistanceTransformAA, upsampleBspline2x } from './edt';

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

describe('upsampleBspline2x', () => {
  it('doubles both dimensions', () => {
    const data = new Float32Array(8 * 4);
    const out = upsampleBspline2x(data, 8, 4);
    expect(out.length).toBe(16 * 8);
  });

  it('preserves constants exactly', () => {
    const data = new Float32Array(6 * 6).fill(3.5);
    const out = upsampleBspline2x(data, 6, 6);
    for (const v of out) expect(v).toBeCloseTo(3.5, 6);
  });

  it('reproduces a linear ramp in the interior (B-spline linear precision)', () => {
    const w = 8;
    const h = 4;
    const data = new Float32Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) data[y * w + x] = x;
    const out = upsampleBspline2x(data, w, h);
    for (let oy = 2; oy < 6; oy++) {
      for (let ox = 4; ox < 12; ox++) {
        const fx = (ox + 0.5) / 2 - 0.5;
        expect(out[oy * w * 2 + ox]).toBeCloseTo(fx, 5);
      }
    }
  });

  it('smooths without overshooting a step edge', () => {
    const w = 8;
    const h = 4;
    const data = new Float32Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 4; x < w; x++) data[y * w + x] = 1;
    const out = upsampleBspline2x(data, w, h);
    for (const v of out) {
      expect(v).toBeGreaterThanOrEqual(-1e-6);
      expect(v).toBeLessThanOrEqual(1 + 1e-6);
    }
  });
});
