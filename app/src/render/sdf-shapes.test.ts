import { describe, expect, it } from 'vitest';
import { resampleSdfBspline, type NormalizedSdf } from './sdf-shapes';

/** Build a grid from a function of normalized grid coords (sx right, sy DOWN). */
function gridFrom(w: number, h: number, f: (sx: number, sy: number) => number): NormalizedSdf {
  const data = new Float32Array(w * h);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) data[y * w + x] = f(x / (w - 1), y / (h - 1));
  return { width: w, height: h, aspect: w / h, data };
}

describe('resampleSdfBspline', () => {
  it('reproduces a linear ramp (B-spline linear precision) in the interior', () => {
    // Square grid on a square canvas, fit 1: texture (i,j) maps straight back.
    const grid = gridFrom(16, 16, (sx) => sx);
    const texW = 32;
    const texH = 32;
    const out = resampleSdfBspline(grid, texW, texH, 1, 1);
    for (let j = 8; j < 24; j++) {
      for (let i = 8; i < 24; i++) {
        const u = ((i + 0.5) / texW - 0.5) * 1; // canvas px, aspect 1
        const sx = u / 1 + 0.5;
        expect(out[j * texW + i]).toBeCloseTo(sx, 3);
      }
    }
  });

  it('is vertically oriented like sample(): grid row 0 lands at +py (top)', () => {
    // Grid whose TOP half (rows 0..h/2) is "inside" (positive).
    const grid = gridFrom(16, 16, (_sx, sy) => (sy < 0.5 ? 1 : -1));
    const texW = 16;
    const texH = 16;
    const out = resampleSdfBspline(grid, texW, texH, 1, 1);
    // Texture j high = +py = screen top → should be inside (positive).
    expect(out[13 * texW + 8]).toBeGreaterThan(0);
    expect(out[2 * texW + 8]).toBeLessThan(0);
  });

  it('fills far-outside beyond the image bounds', () => {
    // Wide canvas (aspect 2), square image, fit 1: left/right margins are off-image.
    const grid = gridFrom(8, 8, () => 1);
    const texW = 32;
    const texH = 16;
    const out = resampleSdfBspline(grid, texW, texH, 2, 1);
    expect(out[8 * texW + 0]).toBeLessThan(0); // far left margin
    expect(out[8 * texW + 31]).toBeLessThan(0); // far right margin
    expect(out[8 * texW + 16]).toBeGreaterThan(0); // center on-image
  });

  it('scales distances by fit (s·d(p/s))', () => {
    const grid = gridFrom(16, 16, () => 0.4);
    const out1 = resampleSdfBspline(grid, 16, 16, 1, 1);
    const outHalf = resampleSdfBspline(grid, 16, 16, 1, 0.5);
    expect(out1[8 * 16 + 8]).toBeCloseTo(0.4, 4);
    expect(outHalf[8 * 16 + 8]).toBeCloseTo(0.2, 4);
  });

  it('never overshoots the grid range (no ringing)', () => {
    const grid = gridFrom(16, 16, (sx) => (sx < 0.5 ? 1 : 0));
    const out = resampleSdfBspline(grid, 64, 64, 1, 1);
    for (const v of out) {
      expect(v).toBeGreaterThanOrEqual(-1 - 1e-6); // OUTSIDE fill is -1·fit
      expect(v).toBeLessThanOrEqual(1 + 1e-6);
    }
  });
});
