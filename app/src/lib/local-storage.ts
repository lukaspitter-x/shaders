import { useEffect, useState, type Dispatch, type SetStateAction } from 'react';

/**
 * Per-browser persistence for editor state — the last-open shader, its settings
 * values, the host-shape pick, and UI toggles. Mirrors flip's approach (lazy
 * read on mount, write-on-change effect) but stays local: this is a workbench,
 * so there's no git-tracked "gold" lane — just `localStorage`.
 *
 * Principle (per flip's persistence rule): validate on read, never heal on
 * write. A corrupt or stale value falls back to the caller's default; we never
 * throw, so a quota/JSON error can't break the app or destroy other keys.
 */

/** All keys live under one namespace so they're easy to find and clear. */
export const STORAGE_PREFIX = 'shaders:';

export function readJson<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(STORAGE_PREFIX + key);
    if (raw == null) return fallback;
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export function writeJson(key: string, value: unknown): void {
  try {
    localStorage.setItem(STORAGE_PREFIX + key, JSON.stringify(value));
  } catch {
    // Private mode / quota exceeded — persistence is best-effort, never fatal.
  }
}

/** `useState` that survives reload: seeds from `localStorage`, writes on change. */
export function useLocalStorage<T>(
  key: string,
  initial: T,
): [T, Dispatch<SetStateAction<T>>] {
  const [value, setValue] = useState<T>(() => readJson(key, initial));
  useEffect(() => {
    writeJson(key, value);
  }, [key, value]);
  return [value, setValue];
}
