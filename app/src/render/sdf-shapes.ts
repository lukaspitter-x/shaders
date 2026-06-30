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
export type BuiltinShapeId = 'rounded-rect' | 'circle' | 'blob';

export interface ShapeDef {
  id: string;
  label: string;
  custom: boolean;
  /** Normalized signed distance, positive inside, in centered aspect space. */
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
  ] as [BuiltinShapeId, string][]
).map(([id, label]) => ({
  id,
  label,
  custom: false,
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

/** A precomputed normalized SDF from an uploaded image (units: fraction of height). */
export interface NormalizedSdf {
  width: number;
  height: number;
  aspect: number;
  data: Float32Array;
}

/** Wrap an uploaded image's SDF as a ShapeDef (bilinear, centered at its aspect). */
export function makeCustomShape(sdf: NormalizedSdf, id: string, label: string): ShapeDef {
  const { width: w, height: h, aspect, data } = sdf;
  const OUTSIDE = -1; // far-outside value for out-of-bounds queries
  return {
    id,
    label,
    custom: true,
    sample: (px, py) => {
      const sx = px / aspect + 0.5;
      const sy = py + 0.5;
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
      const py = (y + 0.5) / size - 0.5;
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
