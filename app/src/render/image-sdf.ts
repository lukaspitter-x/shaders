/**
 * Turn an uploaded image into a normalized SDF for use as a host shape.
 * Browser glue around the pure `signedDistanceTransform`: decode → build a
 * binary inside-mask → distance transform → normalize by height.
 *
 * Coverage heuristic: if the image has transparency, inside = alpha; otherwise
 * inside = darkness (black silhouette on white). Anti-aliased edge pixels are
 * kept FRACTIONAL and fed to the sub-pixel distance transform — binarizing
 * them was the source of staircase artifacts in gradient-based shading.
 * Alpha IS coverage for a rasterized shape, so it passes through untouched;
 * only luminance-derived coverage gets a steep ramp around 0.5 so flat gray
 * photo tones don't read as "near edge". The grid stays at raster resolution —
 * smoothing happens at texture-resample time (`resampleSdfBspline`).
 *
 * SVG files bypass `createImageBitmap` (Chrome rejects SVG blobs) and load via
 * an `<img>` + object URL instead. Being vectors, they rasterize AT `maxDim`
 * rather than capped by it, so a small icon still yields a crisp SDF.
 */
import { signedDistanceTransformAA } from './edt';
import { extractSvgPolylines, polysToSdf } from './svg-sdf';
import type { NormalizedSdf } from './sdf-shapes';

/**
 * How to build the field from an SVG: 'exact' traces the vector geometry
 * (see svg-sdf.ts) with silent fallback to raster; 'raster' always
 * rasterizes. Non-SVG inputs are always rasterized.
 */
export type SdfSource = 'exact' | 'raster';

interface DecodedImage {
  source: CanvasImageSource;
  width: number;
  height: number;
  cleanup: () => void;
}

async function decodeImageFile(file: File, maxDim: number): Promise<DecodedImage> {
  const isSvg = file.type === 'image/svg+xml' || /\.svg$/i.test(file.name);
  if (!isSvg) {
    const bitmap = await createImageBitmap(file);
    return {
      source: bitmap,
      width: bitmap.width,
      height: bitmap.height,
      cleanup: () => bitmap.close?.(),
    };
  }

  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    await img.decode();
    // viewBox-only SVGs report 0×0 intrinsic size — fall back to square.
    const iw = img.naturalWidth || maxDim;
    const ih = img.naturalHeight || maxDim;
    return { source: img, width: iw, height: ih, cleanup: () => URL.revokeObjectURL(url) };
  } catch (err) {
    URL.revokeObjectURL(url);
    throw err;
  }
}

export async function imageToSdf(
  file: File,
  maxDim = 1024,
  source: SdfSource = 'exact',
): Promise<NormalizedSdf> {
  const isSvg = file.type === 'image/svg+xml' || /\.svg$/i.test(file.name);

  if (isSvg && source === 'exact') {
    try {
      const extracted = await extractSvgPolylines(await file.text(), maxDim);
      if (!extracted.hasUnsupported && extracted.polys.length > 0) {
        const aspect = extracted.width / extracted.height;
        const gw = aspect >= 1 ? maxDim : Math.max(1, Math.round(maxDim * aspect));
        const gh = aspect >= 1 ? Math.max(1, Math.round(maxDim / aspect)) : maxDim;
        const data = polysToSdf(extracted.polys, extracted.width, extracted.height, gw, gh);
        return { width: gw, height: gh, aspect: gw / gh, data };
      }
      console.info('[sdf] SVG has stroke-only/unfillable elements — using raster mode');
    } catch (err) {
      console.warn('[sdf] exact-from-path failed — falling back to raster', err);
    }
  }
  const decoded = await decodeImageFile(file, maxDim);
  const scale = isSvg
    ? maxDim / Math.max(decoded.width, decoded.height)
    : Math.min(1, maxDim / Math.max(decoded.width, decoded.height));
  const w = Math.max(1, Math.round(decoded.width * scale));
  const h = Math.max(1, Math.round(decoded.height * scale));

  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('2D canvas unavailable');
  ctx.drawImage(decoded.source, 0, 0, w, h);
  decoded.cleanup();
  const { data } = ctx.getImageData(0, 0, w, h);

  let hasAlpha = false;
  for (let i = 3; i < data.length; i += 4) {
    if (data[i] < 250) {
      hasAlpha = true;
      break;
    }
  }

  const coverage = new Float32Array(w * h);
  for (let p = 0, i = 0; p < coverage.length; p++, i += 4) {
    if (hasAlpha) {
      // Rasterizer alpha IS exact coverage — pass it through untouched.
      // (Narrowing it through a ramp discards sub-pixel edge information and
      // shows up as periodic ribs along edges.)
      coverage[p] = data[i + 3] / 255;
    } else {
      const lum = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
      // Steep ramp: keeps the anti-aliased edge fractional while flattening
      // interior gray tones to solid 0/1.
      coverage[p] = Math.min(1, Math.max(0, (1 - lum / 255 - 0.35) / 0.3));
    }
  }

  const sdfPx = signedDistanceTransformAA(coverage, w, h);
  const out = new Float32Array(sdfPx.length);
  for (let i = 0; i < out.length; i++) out[i] = sdfPx[i] / h; // normalize by height

  return { width: w, height: h, aspect: w / h, data: out };
}
