import type { PresetStore } from './types';

export function pickInitialStore(
  working: PresetStore | null | undefined,
  presets: PresetStore | null | undefined,
): PresetStore {
  if (working && typeof working === 'object' && Object.keys(working).length > 0) {
    return working;
  }
  return presets && typeof presets === 'object' ? presets : {};
}

/**
 * Merge this tab's store over what's on disk, per shader entry. Saves write
 * the merge instead of the raw in-memory store, so a tab that only touched
 * one shader can't wipe another tab's work on a different shader. Within
 * the SAME shader entry the last writer still wins.
 */
export function mergeStores(disk: PresetStore, mem: PresetStore): PresetStore {
  return { ...disk, ...mem };
}

export function storesEqual(a: PresetStore, b: PresetStore): boolean {
  return canon(a) === canon(b);
}

export function isSeedOnly(store: PresetStore): boolean {
  const ids = Object.keys(store);
  if (ids.length === 0) return false;
  return ids.every((id) => {
    const presets = store[id]?.presets;
    return Array.isArray(presets) && presets.length === 1 && presets[0]?.name === 'Default';
  });
}

export function wouldClobberWorkingCopy(next: PresetStore, onDisk: PresetStore): boolean {
  if (!isSeedOnly(next)) return false;
  for (const id of Object.keys(onDisk)) {
    const nextEntry = next[id];
    if (!nextEntry) return true;
    if ((onDisk[id]?.presets?.length ?? 0) > (nextEntry.presets?.length ?? 0)) return true;
  }
  return false;
}

function canon(value: unknown): string {
  return JSON.stringify(sortKeys(value));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    const src = value as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(src).sort()) out[key] = sortKeys(src[key]);
    return out;
  }
  return value;
}
