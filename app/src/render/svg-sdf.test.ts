import { describe, expect, it } from 'vitest';
import { polysToSdf, type PathPoly } from './svg-sdf';

/** Closed rectangle polyline, CCW in SVG coords (y down) unless reversed. */
function rect(x0: number, y0: number, x1: number, y1: number, reversed = false): Float32Array {
  const pts = [x0, y0, x1, y0, x1, y1, x0, y1];
  if (reversed) {
    const rev: number[] = [];
    for (let i = pts.length - 2; i >= 0; i -= 2) rev.push(pts[i], pts[i + 1]);
    return new Float32Array(rev);
  }
  return new Float32Array(pts);
}

const at = (sdf: Float32Array, w: number, x: number, y: number) => sdf[y * w + x] * 100; // grid px (h=100)

describe('polysToSdf', () => {
  it('measures exact distances for a square', () => {
    const polys: PathPoly[] = [{ pts: rect(20, 20, 80, 80), evenOdd: false, group: 0 }];
    const sdf = polysToSdf(polys, 100, 100, 100, 100);
    expect(at(sdf, 100, 50, 50)).toBeCloseTo(29.5, 0); // center: 30 to edge, cell center at 50.5
    expect(at(sdf, 100, 10, 50)).toBeCloseTo(-9.5, 0); // outside left
    expect(at(sdf, 100, 20, 50)).toBeCloseTo(0.5, 1); // cell center 20.5, just inside
    expect(at(sdf, 100, 19, 50)).toBeCloseTo(-0.5, 1); // cell center 19.5, just outside
  });

  it('cuts holes with the evenodd rule', () => {
    const polys: PathPoly[] = [
      { pts: rect(10, 10, 90, 90), evenOdd: true, group: 0 },
      { pts: rect(30, 30, 70, 70), evenOdd: true, group: 0 },
    ];
    const sdf = polysToSdf(polys, 100, 100, 100, 100);
    expect(at(sdf, 100, 50, 50)).toBeLessThan(0); // inside the hole
    expect(at(sdf, 100, 50, 50)).toBeCloseTo(-19.5, 0); // 20 to hole edge
    expect(at(sdf, 100, 20, 50)).toBeGreaterThan(0); // in the ring
  });

  it('cuts holes with nonzero rule via reversed winding', () => {
    const polys: PathPoly[] = [
      { pts: rect(10, 10, 90, 90), evenOdd: false, group: 0 },
      { pts: rect(30, 30, 70, 70, true), evenOdd: false, group: 0 },
    ];
    const sdf = polysToSdf(polys, 100, 100, 100, 100);
    expect(at(sdf, 100, 50, 50)).toBeLessThan(0);
    expect(at(sdf, 100, 20, 50)).toBeGreaterThan(0);
  });

  it('unions separate elements (groups)', () => {
    const polys: PathPoly[] = [
      { pts: rect(10, 10, 40, 90), evenOdd: false, group: 0 },
      { pts: rect(60, 10, 90, 90), evenOdd: false, group: 1 },
    ];
    const sdf = polysToSdf(polys, 100, 100, 100, 100);
    expect(at(sdf, 100, 25, 50)).toBeGreaterThan(0);
    expect(at(sdf, 100, 75, 50)).toBeGreaterThan(0);
    expect(at(sdf, 100, 50, 50)).toBeLessThan(0); // gap between them
  });

  it('scales source units into a differently sized grid', () => {
    const polys: PathPoly[] = [{ pts: rect(4, 4, 16, 16), evenOdd: false, group: 0 }];
    const sdf = polysToSdf(polys, 20, 20, 100, 100); // 5x scale
    // Center (10,10) src = (50,50) grid: 6 src units = 30 grid px from edge.
    expect(sdf[50 * 100 + 50] * 100).toBeCloseTo(29.5, 0);
  });
});
