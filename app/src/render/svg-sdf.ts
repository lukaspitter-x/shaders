/**
 * Exact-from-path SDF generation for SVG uploads.
 *
 * Instead of rasterize → coverage → EDT (whose fidelity is capped by the
 * raster), this traces the SVG's actual vector geometry:
 *
 *   1. The browser samples every SVGGeometryElement via `getPointAtLength`
 *      (handles paths, primitives, and transforms uniformly) into dense
 *      polylines — `extractSvgPolylines`, DOM glue.
 *   2. `polysToSdf` (pure, unit-tested) computes the field: sign by scanline
 *      winding (nonzero or evenodd per element, elements unioned), and EXACT
 *      point-to-segment distances seeded into the generalized EDT for
 *      propagation. The silhouette is placed by geometry, not by pixels.
 *
 * Elements with `fill:none` (stroke-only art) can't be represented as filled
 * paths — the extractor reports them so the caller can fall back to raster.
 */
import { edt2dSq } from './edt';

export interface PathPoly {
  /** Closed polyline vertices (x0,y0,x1,y1,…) in source (SVG user) units. */
  pts: Float32Array;
  /** Fill rule of the owning element (subpaths of one element share it). */
  evenOdd: boolean;
  /** Owning element index — one element's subpaths combine, elements union. */
  group: number;
}

const INF = 1e20;

/** Squared distance from point (px,py) to segment (ax,ay)–(bx,by). */
function segDistSq(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax;
  const dy = by - ay;
  const lenSq = dx * dx + dy * dy;
  let t = lenSq > 0 ? ((px - ax) * dx + (py - ay) * dy) / lenSq : 0;
  t = Math.min(1, Math.max(0, t));
  const ex = px - (ax + t * dx);
  const ey = py - (ay + t * dy);
  return ex * ex + ey * ey;
}

/**
 * Signed distance grid (row 0 = image top, positive inside, units: fraction
 * of gridH — matching `imageToSdf`'s output convention).
 */
export function polysToSdf(
  polys: PathPoly[],
  srcW: number,
  srcH: number,
  gridW: number,
  gridH: number,
): Float32Array {
  const sx = gridW / srcW;
  const sy = gridH / srcH;
  const n = gridW * gridH;

  // --- Sign: scanline winding per element group, groups unioned. ---
  // crossings[group][row] = flat list of (x, dir) pairs.
  const groups = new Map<number, { evenOdd: boolean; rows: number[][] }>();
  for (const poly of polys) {
    let g = groups.get(poly.group);
    if (!g) {
      g = { evenOdd: poly.evenOdd, rows: Array.from({ length: gridH }, () => []) };
      groups.set(poly.group, g);
    }
    const pts = poly.pts;
    const count = pts.length / 2;
    for (let i = 0; i < count; i++) {
      const j = (i + 1) % count;
      const ax = pts[i * 2] * sx;
      const ay = pts[i * 2 + 1] * sy;
      const bx = pts[j * 2] * sx;
      const by = pts[j * 2 + 1] * sy;
      if (ay === by) continue;
      const yMin = Math.min(ay, by);
      const yMax = Math.max(ay, by);
      const dir = by > ay ? 1 : -1;
      // Rows whose center (r + 0.5) lies in [yMin, yMax).
      const r0 = Math.max(0, Math.ceil(yMin - 0.5));
      const r1 = Math.min(gridH - 1, Math.ceil(yMax - 0.5) - 1);
      for (let r = r0; r <= r1; r++) {
        const cy = r + 0.5;
        const x = ax + ((cy - ay) * (bx - ax)) / (by - ay);
        g.rows[r].push(x, dir);
      }
    }
  }

  const inside = new Uint8Array(n);
  const spans: { x0: number; x1: number }[] = [];
  for (const g of groups.values()) {
    for (let r = 0; r < gridH; r++) {
      const flat = g.rows[r];
      if (flat.length === 0) continue;
      const m = flat.length / 2;
      const order = Array.from({ length: m }, (_, i) => i).sort((a, b) => flat[a * 2] - flat[b * 2]);
      spans.length = 0;
      let winding = 0;
      let spanStart = 0;
      for (const idx of order) {
        const wasInside = g.evenOdd ? (winding & 1) === 1 : winding !== 0;
        winding += g.evenOdd ? 1 : flat[idx * 2 + 1];
        const isInside = g.evenOdd ? (winding & 1) === 1 : winding !== 0;
        if (!wasInside && isInside) spanStart = flat[idx * 2];
        else if (wasInside && !isInside) spans.push({ x0: spanStart, x1: flat[idx * 2] });
      }
      const row = r * gridW;
      for (const s of spans) {
        // Cells whose center (c + 0.5) lies in [x0, x1).
        const c0 = Math.max(0, Math.ceil(s.x0 - 0.5));
        const c1 = Math.min(gridW - 1, Math.ceil(s.x1 - 0.5) - 1);
        for (let c = c0; c <= c1; c++) inside[row + c] = 1;
      }
    }
  }

  // --- Exact boundary seeds: walk each segment in ≤1-cell steps, visiting a
  // 3×3 neighborhood per step; every visited cell gets its TRUE squared
  // distance to the full segment. Seeds are kept only within ~1 cell of the
  // boundary: the generalized EDT composes as sqrt(a² + b²), which only
  // approximates the true a + b when the seed depth b is small. ---
  const MAX_SEED_SQ = 1.1 * 1.1;
  const seed = new Float64Array(n).fill(INF);
  for (const poly of polys) {
    const pts = poly.pts;
    const count = pts.length / 2;
    for (let i = 0; i < count; i++) {
      const j = (i + 1) % count;
      const ax = pts[i * 2] * sx;
      const ay = pts[i * 2 + 1] * sy;
      const bx = pts[j * 2] * sx;
      const by = pts[j * 2 + 1] * sy;
      const len = Math.hypot(bx - ax, by - ay);
      const steps = Math.max(1, Math.ceil(len));
      for (let s = 0; s <= steps; s++) {
        const t = s / steps;
        const wx = ax + t * (bx - ax);
        const wy = ay + t * (by - ay);
        const cx = Math.floor(wx);
        const cy = Math.floor(wy);
        for (let oy = -1; oy <= 1; oy++) {
          const y = cy + oy;
          if (y < 0 || y >= gridH) continue;
          for (let ox = -1; ox <= 1; ox++) {
            const x = cx + ox;
            if (x < 0 || x >= gridW) continue;
            const d2 = segDistSq(x + 0.5, y + 0.5, ax, ay, bx, by);
            if (d2 > MAX_SEED_SQ) continue;
            const idx = y * gridW + x;
            if (d2 < seed[idx]) seed[idx] = d2;
          }
        }
      }
    }
  }

  // --- Propagate: mirror signedDistanceTransformAA's cost structure, with
  // geometric seeds in place of coverage-derived ones. ---
  const toInside = new Float64Array(n);
  const toOutside = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    if (inside[i]) {
      toInside[i] = 0;
      toOutside[i] = seed[i];
    } else {
      toInside[i] = seed[i];
      toOutside[i] = 0;
    }
  }
  const dIn = edt2dSq(toInside, gridW, gridH);
  const dOut = edt2dSq(toOutside, gridW, gridH);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = (Math.sqrt(dOut[i]) - Math.sqrt(dIn[i])) / gridH;
  }
  return out;
}

export interface ExtractedSvg {
  polys: PathPoly[];
  /** Source dimensions in SVG user units (the viewBox, or width/height). */
  width: number;
  height: number;
  /** True when stroke-only / unfillable elements were found — fall back to raster. */
  hasUnsupported: boolean;
}

const GEOMETRY_SELECTOR = 'path, rect, circle, ellipse, polygon, polyline, line';

/**
 * Sample every geometry element of an SVG into dense closed polylines via
 * `getPointAtLength` (spacing ~0.6 grid cells). Requires the SVG to be
 * mounted in the live DOM (hidden) so `getCTM`/lengths resolve.
 */
export async function extractSvgPolylines(svgText: string, gridLongSide: number): Promise<ExtractedSvg> {
  const doc = new DOMParser().parseFromString(svgText, 'image/svg+xml');
  const svg = doc.documentElement;
  if (svg.nodeName !== 'svg' || doc.querySelector('parsererror')) {
    throw new Error('not a parseable SVG');
  }

  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;left:-100000px;top:0;visibility:hidden;pointer-events:none;';
  const node = document.importNode(svg, true) as unknown as SVGSVGElement;
  host.appendChild(node);
  document.body.appendChild(host);

  try {
    const vb = node.viewBox?.baseVal;
    const width = vb && vb.width > 0 ? vb.width : node.width.baseVal.value || 512;
    const height = vb && vb.height > 0 ? vb.height : node.height.baseVal.value || 512;
    // Make viewport units == user units so getCTM includes only real transforms.
    node.setAttribute('width', String(width));
    node.setAttribute('height', String(height));

    const cellUnits = Math.max(width, height) / gridLongSide;
    const spacing = Math.max(0.6 * cellUnits, 1e-4);

    const polys: PathPoly[] = [];
    let hasUnsupported = false;
    const elements = node.querySelectorAll<SVGGeometryElement>(GEOMETRY_SELECTOR);
    elements.forEach((el, group) => {
      const style = getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden') return;
      if (style.fill === 'none') {
        // Stroke-only art has no fillable interior — exact mode can't do it.
        if (style.stroke !== 'none' && style.stroke !== '') hasUnsupported = true;
        return;
      }
      const evenOdd = style.fillRule === 'evenodd';
      const matrix = el.getCTM();
      const total = el.getTotalLength();
      if (!total || !Number.isFinite(total)) return;

      const steps = Math.min(60000, Math.max(8, Math.ceil(total / spacing)));
      const jumpSq = Math.pow(Math.max(4 * spacing, 4 * (total / steps)), 2);
      let current: number[] = [];
      let prevX = NaN;
      let prevY = NaN;
      const flush = () => {
        if (current.length >= 6) polys.push({ pts: new Float32Array(current), evenOdd, group });
        current = [];
      };
      for (let s = 0; s <= steps; s++) {
        const p = el.getPointAtLength((s / steps) * total);
        let x = p.x;
        let y = p.y;
        if (matrix) {
          const tp = new DOMPoint(x, y).matrixTransform(matrix);
          x = tp.x;
          y = tp.y;
        }
        // A jump much larger than the sample spacing = subpath boundary
        // (getPointAtLength walks straight across M commands).
        if (!Number.isNaN(prevX)) {
          const dx = x - prevX;
          const dy = y - prevY;
          if (dx * dx + dy * dy > jumpSq) flush();
        }
        current.push(x, y);
        prevX = x;
        prevY = y;
      }
      flush();
    });

    return { polys, width, height, hasUnsupported };
  } finally {
    host.remove();
  }
}
