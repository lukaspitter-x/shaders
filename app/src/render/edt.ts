/**
 * Exact Euclidean distance transform (Felzenszwalb & Huttenlocher 2012), used to
 * turn an uploaded shape mask into a signed distance field. Pure (no DOM) so the
 * core is unit-tested; the browser glue (decode → mask) lives in image-sdf.ts.
 */
const INF = 1e20;

/** 1-D squared-distance transform of a sampled cost function `f`. */
function edt1d(f: Float64Array, n: number): Float64Array {
  const d = new Float64Array(n);
  const v = new Int32Array(n);
  const z = new Float64Array(n + 1);
  let k = 0;
  v[0] = 0;
  z[0] = -INF;
  z[1] = INF;
  for (let q = 1; q < n; q++) {
    let s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    while (s <= z[k]) {
      k--;
      s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
    }
    k++;
    v[k] = q;
    z[k] = s;
    z[k + 1] = INF;
  }
  k = 0;
  for (let q = 0; q < n; q++) {
    while (z[k + 1] < q) k++;
    const dx = q - v[k];
    d[q] = dx * dx + f[v[k]];
  }
  return d;
}

/** Squared Euclidean distance from each cell to the nearest zero-cost seed. */
function edt2dSq(cost: Float64Array, w: number, h: number): Float64Array {
  const tmp = new Float64Array(w * h);
  const col = new Float64Array(h);
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) col[y] = cost[y * w + x];
    const d = edt1d(col, h);
    for (let y = 0; y < h; y++) tmp[y * w + x] = d[y];
  }
  const out = new Float64Array(w * h);
  const row = new Float64Array(w);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) row[x] = tmp[y * w + x];
    const d = edt1d(row, w);
    for (let x = 0; x < w; x++) out[y * w + x] = d[x];
  }
  return out;
}

/**
 * Signed distance (in pixels) from a binary mask: **positive inside**
 * (`mask !== 0`), negative outside, ~0 at the boundary. Exact Euclidean.
 */
/**
 * Signed distance (in pixels) from an anti-aliased coverage field (0..1,
 * 1 = fully inside): **positive inside**, negative outside. Fractional edge
 * cells seed the transform at sub-pixel offsets (tiny-sdf style:
 * `(|a - 0.5|)²` as the squared distance from the cell center to the
 * boundary), so a smoothly rasterized edge yields a smooth field instead of
 * the integer staircase a binary mask produces. Reduces exactly to
 * `signedDistanceTransform` for 0/1 coverage.
 */
export function signedDistanceTransformAA(
  coverage: Float32Array,
  w: number,
  h: number,
): Float32Array {
  const toInside = new Float64Array(w * h);
  const toOutside = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) {
    const a = Math.min(1, Math.max(0, coverage[i]));
    if (a >= 1) {
      toInside[i] = 0;
      toOutside[i] = INF;
    } else if (a <= 0) {
      toInside[i] = INF;
      toOutside[i] = 0;
    } else {
      const din = Math.max(0, 0.5 - a);
      const dout = Math.max(0, a - 0.5);
      toInside[i] = din * din;
      toOutside[i] = dout * dout;
    }
  }
  const dInside = edt2dSq(toInside, w, h);
  const dOutside = edt2dSq(toOutside, w, h);
  const out = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) {
    out[i] = Math.sqrt(dOutside[i]) - Math.sqrt(dInside[i]);
  }
  return out;
}

/**
 * Upsample a scalar field 2× with a separable uniform cubic B-spline. The
 * B-spline kernel is C² and never overshoots, so the upsampled field has
 * smooth first derivatives — exactly what gradient-based shading needs. (GPU
 * bilinear over the raw grid has piecewise-constant gradients per texel,
 * which reads as scalloped facets once a shader amplifies the normal.)
 * Output is `2w × 2h`, texel-center aligned (`src = (dst + 0.5)/2 − 0.5`).
 */
export function upsampleBspline2x(data: Float32Array, w: number, h: number): Float32Array {
  const w2 = w * 2;
  const h2 = h * 2;

  // Per-output-coordinate taps and weights (identical for every row/column).
  const prep = (n: number) => {
    const idx = new Int32Array(n * 2 * 4);
    const wgt = new Float64Array(n * 2 * 4);
    for (let o = 0; o < n * 2; o++) {
      const f = (o + 0.5) / 2 - 0.5;
      const i1 = Math.floor(f);
      const t = f - i1;
      const t2 = t * t;
      const t3 = t2 * t;
      const ws = [
        (1 - 3 * t + 3 * t2 - t3) / 6,
        (4 - 6 * t2 + 3 * t3) / 6,
        (1 + 3 * t + 3 * t2 - 3 * t3) / 6,
        t3 / 6,
      ];
      for (let k = 0; k < 4; k++) {
        idx[o * 4 + k] = Math.min(n - 1, Math.max(0, i1 - 1 + k));
        wgt[o * 4 + k] = ws[k];
      }
    }
    return { idx, wgt };
  };

  const X = prep(w);
  const Y = prep(h);

  // Horizontal pass: w2 × h.
  const tmp = new Float32Array(w2 * h);
  for (let y = 0; y < h; y++) {
    const row = y * w;
    for (let ox = 0; ox < w2; ox++) {
      const b = ox * 4;
      tmp[y * w2 + ox] =
        data[row + X.idx[b]] * X.wgt[b] +
        data[row + X.idx[b + 1]] * X.wgt[b + 1] +
        data[row + X.idx[b + 2]] * X.wgt[b + 2] +
        data[row + X.idx[b + 3]] * X.wgt[b + 3];
    }
  }

  // Vertical pass: w2 × h2.
  const out = new Float32Array(w2 * h2);
  for (let oy = 0; oy < h2; oy++) {
    const b = oy * 4;
    const r0 = Y.idx[b] * w2;
    const r1 = Y.idx[b + 1] * w2;
    const r2 = Y.idx[b + 2] * w2;
    const r3 = Y.idx[b + 3] * w2;
    for (let ox = 0; ox < w2; ox++) {
      out[oy * w2 + ox] =
        tmp[r0 + ox] * Y.wgt[b] +
        tmp[r1 + ox] * Y.wgt[b + 1] +
        tmp[r2 + ox] * Y.wgt[b + 2] +
        tmp[r3 + ox] * Y.wgt[b + 3];
    }
  }
  return out;
}

export function signedDistanceTransform(mask: Uint8Array, w: number, h: number): Float32Array {
  const toInside = new Float64Array(w * h);
  const toOutside = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) {
    if (mask[i]) {
      toInside[i] = 0;
      toOutside[i] = INF;
    } else {
      toInside[i] = INF;
      toOutside[i] = 0;
    }
  }
  const dInside = edt2dSq(toInside, w, h); // dist to nearest inside cell
  const dOutside = edt2dSq(toOutside, w, h); // dist to nearest outside cell
  const out = new Float32Array(w * h);
  for (let i = 0; i < w * h; i++) {
    out[i] = mask[i] ? Math.sqrt(dOutside[i]) : -Math.sqrt(dInside[i]);
  }
  return out;
}
