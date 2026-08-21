import type { PresetStore } from './types';
import { isSeedOnly, mergeStores, pickInitialStore, wouldClobberWorkingCopy } from './working-store';

const PRESETS_ENDPOINT = '/api/sessions';
const WORKING_ENDPOINT = '/api/working';

async function getJson(endpoint: string): Promise<PresetStore> {
  try {
    const res = await fetch(endpoint, { cache: 'no-store' });
    if (!res.ok) return {};
    const data = (await res.json()) as PresetStore;
    return data && typeof data === 'object' ? data : {};
  } catch {
    return {};
  }
}

export async function loadStores(): Promise<{ store: PresetStore; committed: PresetStore }> {
  const [working, committed] = await Promise.all([
    getJson(WORKING_ENDPOINT),
    getJson(PRESETS_ENDPOINT),
  ]);
  return { store: pickInitialStore(working, committed), committed };
}

export async function saveStore(store: PresetStore): Promise<void> {
  try {
    // Read-merge-write: keep shader entries another tab wrote that this tab
    // never loaded, instead of clobbering the whole file with our view.
    const onDisk = await getJson(WORKING_ENDPOINT);
    if (isSeedOnly(store) && wouldClobberWorkingCopy(store, onDisk)) {
      console.warn(
        '[shaders] Skipped auto-save: a fresh/seed store would have overwritten your ' +
          'populated working copy. Your saved presets on disk are preserved — reload to pick them up.',
      );
      return;
    }
    await fetch(WORKING_ENDPOINT, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(mergeStores(onDisk, store)),
    });
  } catch (err) {
    console.error('Failed to save working presets', err);
  }
}

export async function savePresets(store: PresetStore): Promise<void> {
  const onDisk = await getJson(PRESETS_ENDPOINT);
  const res = await fetch(PRESETS_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(mergeStores(onDisk, store)),
  });
  if (!res.ok) throw new Error(`Save presets failed: ${res.status}`);
}

/**
 * Last-gasp write on pagehide. Can't read-merge inside an unload handler
 * (sendBeacon is fire-and-forget), so this posts the raw store — the clobber
 * window is only edits another tab made since our last merged autosave
 * (≤ the 300ms debounce), which the other tab's own autosave re-merges.
 */
export function flushStore(store: PresetStore): void {
  const body = JSON.stringify(store);
  try {
    if (typeof navigator !== 'undefined' && navigator.sendBeacon) {
      navigator.sendBeacon(WORKING_ENDPOINT, new Blob([body], { type: 'application/json' }));
    } else {
      void fetch(WORKING_ENDPOINT, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
        keepalive: true,
      });
    }
  } catch {
    /* best-effort */
  }
}
