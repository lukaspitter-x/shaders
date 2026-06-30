/**
 * Turn an uploaded image into a normalized SDF for use as a host shape.
 * Browser glue around the pure `signedDistanceTransform`: decode → build a
 * binary inside-mask → distance transform → normalize by height.
 *
 * Mask heuristic: if the image has transparency, inside = opaque (alpha ≥ 128);
 * otherwise inside = dark (luminance < 128), i.e. a black silhouette on white.
 */
import { signedDistanceTransform } from './edt';
import type { NormalizedSdf } from './sdf-shapes';

export async function imageToSdf(file: File, maxDim = 256): Promise<NormalizedSdf> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height));
  const w = Math.max(1, Math.round(bitmap.width * scale));
  const h = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('2D canvas unavailable');
  ctx.drawImage(bitmap, 0, 0, w, h);
  bitmap.close?.();
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
