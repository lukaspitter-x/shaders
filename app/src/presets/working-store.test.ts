import { describe, expect, it } from 'vitest';
import { mergeStores } from './working-store';
import type { PresetStore } from './types';

const entry = (shaderId: string, name: string): PresetStore[string] => ({
  shaderId,
  activePresetId: 'p1',
  presets: [{ id: 'p1', name, createdAt: 1, values: {} }],
});

describe('mergeStores', () => {
  it('keeps disk-only shader entries another tab wrote', () => {
    const disk = { chrome: entry('chrome', 'Mine'), thermal: entry('thermal', 'Other tab') };
    const mem = { chrome: entry('chrome', 'Mine v2') };
    const out = mergeStores(disk, mem);
    expect(out.thermal.presets[0].name).toBe('Other tab');
    expect(out.chrome.presets[0].name).toBe('Mine v2');
  });

  it('memory wins per shader entry', () => {
    const disk = { chrome: entry('chrome', 'Stale') };
    const mem = { chrome: entry('chrome', 'Fresh') };
    expect(mergeStores(disk, mem).chrome.presets[0].name).toBe('Fresh');
  });

  it('tolerates empty stores', () => {
    expect(mergeStores({}, {})).toEqual({});
    const mem = { chrome: entry('chrome', 'A') };
    expect(mergeStores({}, mem)).toEqual(mem);
  });
});
