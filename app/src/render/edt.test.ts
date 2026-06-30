import { describe, expect, it } from 'vitest';
import { signedDistanceTransform } from './edt';

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
