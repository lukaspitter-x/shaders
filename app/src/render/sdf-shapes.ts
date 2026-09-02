/**
 * Host shapes for previewing fills. A Pencil shader fill is applied to a layer
 * and clipped to that layer's silhouette; `@sdf` shaders additionally read the
 * layer's signed-distance field (`u_shape`). We synthesize that field here.
 *
 * A `ShapeDef` exposes `sample(px, py)` — the normalized signed distance,
 * **positive inside**, in a centered aspect space where y ∈ [-0.5, 0.5] spans
 * the canvas height and x is aspect-corrected. Built-ins are analytic; uploads
 * (see image-sdf.ts) bilinear-sample a precomputed grid. `null` shape = "None /
 * full background" (no clip, empty SDF — the plain-rectangle case from D8).
 *
 * Pure module (math only) so it's cheap to regenerate and unit-testable.
 */
export type BuiltinShapeId = 'rounded-rect' | 'circle' | 'blob' | 'full-frame';

export interface ShapeDef {
  id: string;
  label: string;
  custom: boolean;
  /** False when the shape is defined to cover the viewport and cannot be resized. */
  scalable?: boolean;
  /** Source image aspect (w/h) for custom uploads — drives fit-to-canvas. */
  aspect?: number;
  /** Custom uploads: the raw SDF grid, for high-quality texture resampling. */
  grid?: NormalizedSdf;
  /**
   * Normalized signed distance, positive inside, in centered aspect space.
   * +py is UP (gl_FragCoord convention) — consumers that iterate rows
   * top-down (thumbnails) must flip.
   */
  sample: (px: number, py: number) => number;
}

function sdRoundBox(px: number, py: number, bx: number, by: number, r: number): number {
  const qx = Math.abs(px) - bx + r;
  const qy = Math.abs(py) - by + r;
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
}

/** Smooth-min (polynomial) for blending exterior distance fields into a union. */
function smin(a: number, b: number, k: number): number {
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return Math.min(a, b) - h * h * k * 0.25;
}

/**
 * Normalized signed distance, positive inside (y ∈ [-0.5, 0.5]). Shapes are kept
 * within ~±0.4 so the glow has room to fall off inside the canvas.
 */
function builtinDistance(id: BuiltinShapeId, px: number, py: number): number {
  switch (id) {
    // The whole canvas is the host (a real positive-inside rect SDF, not "None"):
    // distance to the top/bottom edges, positive across the full frame at any
    // aspect (sample() has no aspect, so the known vertical span ±0.5 drives it).
    case 'full-frame':
      return 0.5 - Math.abs(py);
    case 'circle':
      return 0.38 - Math.hypot(px, py);
    case 'rounded-rect':
      return -sdRoundBox(px, py, 0.34, 0.3, 0.11);
    case 'blob': {
      const e1 = Math.hypot(px + 0.09, py - 0.0) - 0.2;
      const e2 = Math.hypot(px - 0.13, py - 0.07) - 0.17;
      const e3 = Math.hypot(px - 0.02, py + 0.13) - 0.15;
      return -smin(smin(e1, e2, 0.15), e3, 0.15);
    }
  }
}

export const BUILTIN_SHAPES: ShapeDef[] = (
  [
    ['rounded-rect', 'Rounded rect'],
    ['circle', 'Circle'],
    ['blob', 'Blob'],
    ['full-frame', 'Full frame'],
  ] as [BuiltinShapeId, string][]
).map(([id, label]) => ({
  id,
  label,
  custom: false,
  scalable: id !== 'full-frame',
  sample: (px: number, py: number) => builtinDistance(id, px, py),
}));

/**
 * Generate the SDF as a Float32Array (one R channel per texel, row-major) sized
 * `texW × texH`. `aspect` is canvasW/canvasH; `pxScale` is the canvas height in
 * device pixels (the unit the marcher expects). Distances are stored in
 * canvas-pixel units regardless of the texture's own resolution.
 */
export function generateSdf(
  shape: ShapeDef,
  texW: number,
  texH: number,
  aspect: number,
  pxScale: number,
): Float32Array {
  const data = new Float32Array(texW * texH);
  for (let j = 0; j < texH; j++) {
    const v = (j + 0.5) / texH - 0.5;
    for (let i = 0; i < texW; i++) {
      const u = ((i + 0.5) / texW - 0.5) * aspect;
      data[j * texW + i] = shape.sample(u, v) * pxScale;
    }
  }
  return data;
}

/**
 * Bounding box of the shape (texels with positive distance) as fractions of
 * the field's size, `y0` at the bottom row (+py up, gl_FragCoord convention).
 * Pencil hands a fill its *layer* bounds as `u_resolution`; the workbench
 * uses this box to emulate that for a host shape. `null` when the field is
 * empty (no shape / plain rectangle).
 */
export function sdfBounds(
  data: Float32Array,
  width: number,
  height: number,
): { x0: number; y0: number; x1: number; y1: number } | null {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y++) {
    const row = y * width;
    for (let x = 0; x < width; x++) {
      if (data[row + x] > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return { x0: minX / width, y0: minY / height, x1: (maxX + 1) / width, y1: (maxY + 1) / height };
}

/** A precomputed normalized SDF from an uploaded image (units: fraction of height). */
export interface NormalizedSdf {
  width: number;
  height: number;
  aspect: number;
  data: Float32Array;
}

/** Uniform cubic B-spline weights for fractional offset t ∈ [0,1). */
function bsplineWeights(t: number): [number, number, number, number] {
  const t2 = t * t;
  const t3 = t2 * t;
  return [
    (1 - 3 * t + 3 * t2 - t3) / 6,
    (4 - 6 * t2 + 3 * t3) / 6,
    (1 + 3 * t + 3 * t2 - 3 * t3) / 6,
    t3 / 6,
  ];
}

const OUTSIDE = -1; // far-outside value (normalized units) for off-image texels

/**
 * Resample an uploaded shape's SDF grid into a canvas-space texture with a
 * separable uniform cubic B-spline. This replaces bilinear `sample()` on the
 * hot path: bilinear has gradient kinks at every grid-cell boundary, which a
 * Sobel-normal shader renders as sawtooth facets once the shape is zoomed so
 * one grid cell spans several canvas pixels. The B-spline kernel is C² (no
 * kinks), never overshoots, and reproduces linear ramps — a true SDF passes
 * through nearly unchanged.
 *
 * Mapping matches `makeCustomShape.sample` + the viewport's fit wrapper
 * (`s·d(p/s)`): texture texel (i,j) → centered canvas coords (+py up) →
 * ÷fit → image-aspect space → grid coords (row 0 = image top). Returned
 * values are in the grid's normalized units, already multiplied by `fit`;
 * off-image texels get `OUTSIDE·fit`.
 */
export function resampleSdfBspline(
  grid: NormalizedSdf,
  texW: number,
  texH: number,
  canvasAspect: number,
  fit: number,
): Float32Array {
  const { width: w, height: h, aspect, data } = grid;

  // Per-column and per-row taps/weights (the mapping is affine per axis).
  const prepAxis = (nOut: number, coord: (o: number) => number, nSrc: number) => {
    const idx = new Int32Array(nOut * 4);
    const wgt = new Float64Array(nOut * 4);
    const valid = new Uint8Array(nOut);
    for (let o = 0; o < nOut; o++) {
      const s = coord(o); // normalized 0..1 across the image
      if (s < 0 || s > 1) continue;
      valid[o] = 1;
      const f = s * (nSrc - 1);
      const i1 = Math.floor(f);
      const ws = bsplineWeights(f - i1);
      for (let k = 0; k < 4; k++) {
        idx[o * 4 + k] = Math.min(nSrc - 1, Math.max(0, i1 - 1 + k));
        wgt[o * 4 + k] = ws[k];
      }
    }
    return { idx, wgt, valid };
  };

  const X = prepAxis(
    texW,
    (i) => (((i + 0.5) / texW - 0.5) * canvasAspect) / fit / aspect + 0.5,
    w,
  );
  const Y = prepAxis(
    texH,
    // +py up; grid row 0 is the image top → sy = 0.5 − py.
    (j) => 0.5 - ((j + 0.5) / texH - 0.5) / fit,
    h,
  );

  // Horizontal pass: texW × h.
  const tmp = new Float32Array(texW * h);
  for (let y = 0; y < h; y++) {
    const row = y * w;
    for (let i = 0; i < texW; i++) {
      if (!X.valid[i]) continue;
      const b = i * 4;
      tmp[y * texW + i] =
        data[row + X.idx[b]] * X.wgt[b] +
        data[row + X.idx[b + 1]] * X.wgt[b + 1] +
        data[row + X.idx[b + 2]] * X.wgt[b + 2] +
        data[row + X.idx[b + 3]] * X.wgt[b + 3];
    }
  }

  // Vertical pass: texW × texH.
  const out = new Float32Array(texW * texH);
  for (let j = 0; j < texH; j++) {
    const b = j * 4;
    const rowOut = j * texW;
    if (!Y.valid[j]) {
      for (let i = 0; i < texW; i++) out[rowOut + i] = OUTSIDE * fit;
      continue;
    }
    const r0 = Y.idx[b] * texW;
    const r1 = Y.idx[b + 1] * texW;
    const r2 = Y.idx[b + 2] * texW;
    const r3 = Y.idx[b + 3] * texW;
    for (let i = 0; i < texW; i++) {
      out[rowOut + i] = X.valid[i]
        ? (tmp[r0 + i] * Y.wgt[b] +
            tmp[r1 + i] * Y.wgt[b + 1] +
            tmp[r2 + i] * Y.wgt[b + 2] +
            tmp[r3 + i] * Y.wgt[b + 3]) *
          fit
        : OUTSIDE * fit;
    }
  }
  return out;
}

/** Wrap an uploaded image's SDF as a ShapeDef (bilinear, centered at its aspect). */
export function makeCustomShape(sdf: NormalizedSdf, id: string, label: string): ShapeDef {
  const { width: w, height: h, aspect, data } = sdf;
  const OUTSIDE = -1; // far-outside value for out-of-bounds queries
  return {
    id,
    label,
    custom: true,
    aspect,
    grid: sdf,
    sample: (px, py) => {
      const sx = px / aspect + 0.5;
      // Grid row 0 is the image TOP; +py is up — flip so the image isn't
      // rendered upside down under gl_FragCoord's bottom-up y.
      const sy = 0.5 - py;
      if (sx < 0 || sx > 1 || sy < 0 || sy > 1) return OUTSIDE;
      const fx = sx * (w - 1);
      const fy = sy * (h - 1);
      const x0 = Math.floor(fx);
      const y0 = Math.floor(fy);
      const x1 = Math.min(w - 1, x0 + 1);
      const y1 = Math.min(h - 1, y0 + 1);
      const tx = fx - x0;
      const ty = fy - y0;
      const a = data[y0 * w + x0];
      const b = data[y0 * w + x1];
      const c = data[y1 * w + x0];
      const d = data[y1 * w + x1];
      return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
    },
  };
}

/**
 * Draw a small silhouette thumbnail of a shape (or a filled square for `null` =
 * "None / full background") into a square canvas. Samples the shape over a
 * unit-aspect square with a ~1px anti-aliased edge.
 */
export function drawShapeThumbnail(canvas: HTMLCanvasElement, shape: ShapeDef | null, size = 36): void {
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const img = ctx.createImageData(size, size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const px = (x + 0.5) / size - 0.5;
      // Canvas rows go top-down; sample() expects +py up.
      const py = 0.5 - (y + 0.5) / size;
      // None → full background: fill the whole tile.
      const d = shape ? shape.sample(px, py) : 0.5;
      const alpha = Math.max(0, Math.min(1, d * size * 1.4 + 0.5));
      const o = (y * size + x) * 4;
      img.data[o] = 255;
      img.data[o + 1] = 255;
      img.data[o + 2] = 255;
      img.data[o + 3] = Math.round(alpha * 210);
    }
  }
  ctx.putImageData(img, 0, 0);
}
