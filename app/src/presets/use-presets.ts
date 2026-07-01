import { useCallback, useEffect, useMemo, useSyncExternalStore } from 'react';
import type { Preset, PresetStore, ShaderPresets } from './types';
import type { ShaderValues } from '@/glsl/parse-annotations';
import { sanitizeValues } from '@/glsl/parse-annotations';
import type { SettingsSchema } from '@/settings/schema';
import { loadStores, saveStore, savePresets, flushStore } from './persistence';
import { storesEqual } from './working-store';
import {
  canRedo as histCanRedo,
  canUndo as histCanUndo,
  emptyHistory,
  record,
  redo as redoHistory,
  undo as undoHistory,
  type History,
} from '@/lib/history';

const AUTOSAVE_MS = 300;

let current: PresetStore = {};
let committed: PresetStore = {};
let workingDirty = false;
let loaded = false;
let loading: Promise<void> | null = null;
let pendingSave = false;
const listeners = new Set<() => void>();
let saveTimer: ReturnType<typeof setTimeout> | null = null;

let snapshot: { store: PresetStore; dirty: boolean } = { store: current, dirty: workingDirty };
function refreshSnapshot() {
  snapshot = { store: current, dirty: workingDirty };
}

function notify() {
  for (const l of listeners) l();
}

function scheduleSave() {
  pendingSave = true;
  if (saveTimer !== null) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    saveTimer = null;
    pendingSave = false;
    void saveStore(current);
  }, AUTOSAVE_MS);
}

function flushPending() {
  if (!loaded || !pendingSave) return;
  if (saveTimer !== null) {
    clearTimeout(saveTimer);
    saveTimer = null;
  }
  pendingSave = false;
  flushStore(current);
}

if (typeof window !== 'undefined') {
  window.addEventListener('pagehide', flushPending);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') flushPending();
  });
}

function update(next: PresetStore) {
  current = next;
  workingDirty = true;
  refreshSnapshot();
  notify();
  scheduleSave();
}

function ensureLoaded(): Promise<void> {
  if (loaded) return Promise.resolve();
  if (loading) return loading;
  loading = loadStores().then(({ store, committed: c }) => {
    current = { ...store, ...current };
    committed = structuredClone(c);
    loaded = true;
    workingDirty = !storesEqual(current, committed);
    refreshSnapshot();
    notify();
  });
  return loading;
}

function uid(): string {
  const [a, b] = crypto.getRandomValues(new Uint32Array(2));
  return a.toString(36) + b.toString(36);
}

function seedShader(shaderId: string, defaults: ShaderValues) {
  if (current[shaderId]) return;
  const preset: Preset = {
    id: uid(),
    name: 'Default',
    createdAt: Date.now(),
    values: structuredClone(defaults),
  };
  const entry: ShaderPresets = {
    shaderId,
    activePresetId: preset.id,
    presets: [preset],
  };
  current = { ...current, [shaderId]: entry };
  refreshSnapshot();
  notify();
}

function setEntry(shaderId: string, mutate: (entry: ShaderPresets) => ShaderPresets) {
  const entry = current[shaderId];
  if (!entry) return;
  update({ ...current, [shaderId]: mutate(entry) });
}

// --- undo/redo history (per active preset) ---

const histories = new Map<string, History<ShaderValues>>();
const histKeyFor = (shaderId: string, presetId: string) => `${shaderId} ${presetId}`;

function activeOf(shaderId: string): Preset | null {
  const entry = current[shaderId];
  return entry?.presets.find((p) => p.id === entry.activePresetId) ?? null;
}

function recordHistory(shaderId: string, token: string) {
  const active = activeOf(shaderId);
  if (!active) return;
  const key = histKeyFor(shaderId, active.id);
  histories.set(
    key,
    record(histories.get(key) ?? emptyHistory<ShaderValues>(), structuredClone(active.values), token, performance.now()),
  );
}

function applyActiveValues(shaderId: string, values: ShaderValues) {
  const entry = current[shaderId];
  if (!entry) return;
  update({
    ...current,
    [shaderId]: {
      ...entry,
      presets: entry.presets.map((p) =>
        p.id === entry.activePresetId ? { ...p, values } : p,
      ),
    },
  });
}

function undoActive(shaderId: string) {
  const active = activeOf(shaderId);
  if (!active) return;
  const key = histKeyFor(shaderId, active.id);
  const h = histories.get(key);
  if (!h) return;
  const res = undoHistory(h, structuredClone(active.values));
  if (!res) return;
  histories.set(key, res.history);
  applyActiveValues(shaderId, res.restore);
}

function redoActive(shaderId: string) {
  const active = activeOf(shaderId);
  if (!active) return;
  const key = histKeyFor(shaderId, active.id);
  const h = histories.get(key);
  if (!h) return;
  const res = redoHistory(h, structuredClone(active.values));
  if (!res) return;
  histories.set(key, res.history);
  applyActiveValues(shaderId, res.restore);
}

export interface UsePresets {
  presets: Preset[];
  active: Preset | null;
  values: ShaderValues;
  ready: boolean;
  setValue: (key: string, value: ShaderValues[string]) => void;
  createPreset: (name?: string) => void;
  duplicatePreset: (id?: string) => void;
  deletePreset: (id: string) => void;
  renamePreset: (id: string, name: string) => void;
  switchPreset: (id: string) => void;
  undo: () => void;
  redo: () => void;
  canUndo: boolean;
  canRedo: boolean;
  dirty: boolean;
  commitPresets: () => void;
  revertToPresets: () => void;
}

export function usePresets(
  shaderId: string,
  defaults: ShaderValues,
  schema?: SettingsSchema<ShaderValues>,
): UsePresets {
  const snap = useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => snapshot,
    () => snapshot,
  );
  const store = snap.store;
  const dirty = snap.dirty;

  useEffect(() => {
    void ensureLoaded();
  }, []);

  useEffect(() => {
    if (loaded && !current[shaderId]) seedShader(shaderId, defaults);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [snap, shaderId]);

  const entry = store[shaderId];
  const presets = entry?.presets ?? [];
  const active = entry?.presets.find((p) => p.id === entry.activePresetId) ?? null;

  const values: ShaderValues = useMemo(() => {
    const raw = active?.values;
    if (raw === undefined) return defaults;
    const merged = { ...defaults, ...raw };
    if (!schema) return merged;
    return sanitizeValues(schema, merged);
  }, [active?.values, defaults, schema]);

  const ready = !!entry;

  const hist = active ? histories.get(histKeyFor(shaderId, active.id)) : undefined;
  const undo = useCallback(() => undoActive(shaderId), [shaderId]);
  const redo = useCallback(() => redoActive(shaderId), [shaderId]);

  const commitPresetsAction = useCallback(() => {
    void (async () => {
      try {
        await savePresets(current);
        committed = structuredClone(current);
        workingDirty = false;
        refreshSnapshot();
        notify();
      } catch (err) {
        console.error('Failed to commit presets', err);
      }
    })();
  }, []);

  const revertToPresetsAction = useCallback(() => {
    current = structuredClone(committed);
    workingDirty = false;
    refreshSnapshot();
    notify();
    scheduleSave();
  }, []);

  const setValue = useCallback(
    (key: string, value: ShaderValues[string]) => {
      recordHistory(shaderId, `set:${key}`);
      setEntry(shaderId, (e) => ({
        ...e,
        presets: e.presets.map((p) =>
          p.id === e.activePresetId
            ? { ...p, values: { ...p.values, [key]: value } }
            : p,
        ),
      }));
    },
    [shaderId],
  );

  const createPreset = useCallback(
    (name?: string) => {
      const id = uid();
      const preset: Preset = {
        id,
        name: name ?? `Preset ${presets.length + 1}`,
        createdAt: Date.now(),
        values: structuredClone(defaults),
      };
      setEntry(shaderId, (e) => ({
        ...e,
        activePresetId: id,
        presets: [...e.presets, preset],
      }));
    },
    [shaderId, presets.length, defaults],
  );

  const duplicatePreset = useCallback(
    (id?: string) => {
      const srcId = id ?? entry?.activePresetId;
      const src = entry?.presets.find((p) => p.id === srcId);
      if (!src) return;
      const newId = uid();
      const copy: Preset = {
        id: newId,
        name: `${src.name} copy`,
        createdAt: Date.now(),
        values: structuredClone(src.values),
      };
      setEntry(shaderId, (e) => ({
        ...e,
        activePresetId: newId,
        presets: [...e.presets, copy],
      }));
    },
    [shaderId, entry],
  );

  const deletePreset = useCallback(
    (id: string) => {
      const e0 = current[shaderId];
      if (e0 && e0.presets.length > 1) histories.delete(histKeyFor(shaderId, id));
      setEntry(shaderId, (e) => {
        if (e.presets.length <= 1) return e;
        const remaining = e.presets.filter((p) => p.id !== id);
        const activePresetId =
          e.activePresetId === id ? remaining[0].id : e.activePresetId;
        return { ...e, activePresetId, presets: remaining };
      });
    },
    [shaderId],
  );

  const renamePreset = useCallback(
    (id: string, name: string) => {
      setEntry(shaderId, (e) => ({
        ...e,
        presets: e.presets.map((p) => (p.id === id ? { ...p, name } : p)),
      }));
    },
    [shaderId],
  );

  const switchPreset = useCallback(
    (id: string) => {
      setEntry(shaderId, (e) => ({ ...e, activePresetId: id }));
    },
    [shaderId],
  );

  return {
    presets,
    active,
    values,
    ready,
    setValue,
    createPreset,
    duplicatePreset,
    deletePreset,
    renamePreset,
    switchPreset,
    undo,
    redo,
    canUndo: histCanUndo(hist),
    canRedo: histCanRedo(hist),
    dirty,
    commitPresets: commitPresetsAction,
    revertToPresets: revertToPresetsAction,
  };
}
