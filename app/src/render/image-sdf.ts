/**
 * Turn an uploaded image into a normalized SDF for use as a host shape.
 * Browser glue around the pure `signedDistanceTransform`: decode → build a
 * binary inside-mask → distance transform → normalize by height.
 *
 * Mask heuristic: if the image has transparency, inside = opaque (alpha ≥ 128);
 * otherwise inside = dark (luminance < 128), i.e. a black silhouette on white.
 *
 * SVG files bypass `createImageBitmap` (Chrome rejects SVG blobs) and load via
 * an `<img>` + object URL instead. Being vectors, they rasterize AT `maxDim`
 * rather than capped by it, so a small icon still yields a crisp SDF.
 */
import { signedDistanceTransform } from './edt';
import type { NormalizedSdf } from './sdf-shapes';

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

export async function imageToSdf(file: File, maxDim = 512): Promise<NormalizedSdf> {
  const isSvg = file.type === 'image/svg+xml' || /\.svg$/i.test(file.name);
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

  const mask = new Uint8Array(w * h);
  for (let p = 0, i = 0; p < mask.length; p++, i += 4) {
    if (hasAlpha) {
      mask[p] = data[i + 3] >= 128 ? 1 : 0;
    } else {
      const lum = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
      mask[p] = lum < 128 ? 1 : 0;
    }
  }

  const sdfPx = signedDistanceTransform(mask, w, h);
  const out = new Float32Array(w * h);
  for (let i = 0; i < out.length; i++) out[i] = sdfPx[i] / h; // normalize by height

  return { width: w, height: h, aspect: w / h, data: out };
}
