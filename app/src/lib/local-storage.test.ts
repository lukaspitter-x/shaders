import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { readJson, writeJson, STORAGE_PREFIX } from './local-storage';

// The project's test env is node (pure cores), so there's no DOM localStorage.
// A tiny in-memory stand-in lets us exercise the read/write logic directly.
function installFakeStorage(): Map<string, string> {
  const map = new Map<string, string>();
  const fake = {
    getItem: (k: string) => (map.has(k) ? map.get(k)! : null),
    setItem: (k: string, v: string) => void map.set(k, v),
    removeItem: (k: string) => void map.delete(k),
    clear: () => map.clear(),
  };
  Object.defineProperty(globalThis, 'localStorage', { value: fake, configurable: true });
  return map;
}

let store: Map<string, string>;
beforeEach(() => {
  store = installFakeStorage();
});
afterEach(() => {
  delete (globalThis as { localStorage?: unknown }).localStorage;
});

describe('readJson / writeJson', () => {
  it('round-trips values under the namespaced key', () => {
    writeJson('values:demo', { gain: 0.5, tint: '#ff0000' });
    expect(store.get(STORAGE_PREFIX + 'values:demo')).toBe('{"gain":0.5,"tint":"#ff0000"}');
    expect(readJson('values:demo', null)).toEqual({ gain: 0.5, tint: '#ff0000' });
  });

  it('returns the fallback for a missing key', () => {
    expect(readJson('nope', 'default')).toBe('default');
  });

  it('returns the fallback for corrupt JSON instead of throwing', () => {
    store.set(STORAGE_PREFIX + 'broken', '{not json');
    expect(readJson('broken', 42)).toBe(42);
  });

  it('never throws when writing fails (quota / private mode)', () => {
    localStorage.setItem = () => {
      throw new DOMException('QuotaExceededError');
    };
    expect(() => writeJson('x', { big: 'data' })).not.toThrow();
  });
});
