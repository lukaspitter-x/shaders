/**
 * Persistence for uploaded host shapes. The original file is stored as a
 * data URL in `src/data/shapes.local.json` (gitignored, like the working
 * preset store) via the dev server's `/api/shapes` JSON endpoint, and the
 * SDF is recomputed from it on startup — so uploads survive refresh and
 * restart at full fidelity, and improvements to the SDF pipeline apply
 * retroactively to old uploads.
 */

export interface StoredShape {
  id: string;
  label: string;
  /** Original file name + MIME type, so restore can rebuild a real File. */
  name: string;
  type: string;
  dataUrl: string;
}

const ENDPOINT = '/api/shapes';

/** Data-URL payloads above this size are kept session-only (JSON store). */
const MAX_PERSIST_BYTES = 4 * 1024 * 1024;

async function getStore(): Promise<Record<string, StoredShape>> {
  try {
    const res = await fetch(ENDPOINT, { cache: 'no-store' });
    if (!res.ok) return {};
    const data = (await res.json()) as Record<string, StoredShape>;
    return data && typeof data === 'object' ? data : {};
  } catch {
    return {};
  }
}

export async function loadStoredShapes(): Promise<StoredShape[]> {
  const store = await getStore();
  return Object.values(store).filter(
    (s) => s && typeof s.id === 'string' && typeof s.dataUrl === 'string',
  );
}

/** Read-merge-write (single-user workbench; last write wins). */
export async function persistShape(shape: StoredShape): Promise<void> {
  if (shape.dataUrl.length > MAX_PERSIST_BYTES) {
    console.warn(`[shapes] "${shape.label}" is too large to persist — kept for this session only.`);
    return;
  }
  const store = await getStore();
  store[shape.id] = shape;
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(store),
  });
  if (!res.ok) throw new Error(`persist shape failed: ${res.status}`);
}

export async function removeStoredShape(id: string): Promise<void> {
  const store = await getStore();
  if (!(id in store)) return;
  delete store[id];
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(store),
  });
  if (!res.ok) throw new Error(`remove shape failed: ${res.status}`);
}

export function fileToDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result as string);
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}

export async function storedShapeToFile(s: StoredShape): Promise<File> {
  const blob = await (await fetch(s.dataUrl)).blob();
  return new File([blob], s.name, { type: s.type || blob.type });
}
