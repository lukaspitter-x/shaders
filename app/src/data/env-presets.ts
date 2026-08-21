/**
 * Bundled environment-map presets for `sampler2D` uniforms tagged
 * `@assets env` (a workbench-only directive; stripped on Pencil export).
 *
 * Two tiers: `/env/` is committed (Poly Haven, CC0); `/env-local/` is the
 * Greyscalegorilla Pro Studios Metal set, tone-mapped locally and gitignored
 * (EULA forbids redistribution — see `public/env-local/README.md`). Thumbnails
 * for missing local files hide themselves via img onerror.
 */
export interface AssetPreset {
  id: string;
  label: string;
  url: string;
}

const METAL_COUNT = 45;

export const ENV_PRESETS: AssetPreset[] = [
  { id: 'brown-studio', label: 'Studio Room', url: '/env/brown-studio.jpg' },
  { id: 'neon-studio', label: 'Neon Room', url: '/env/neon-studio.jpg' },
  ...Array.from({ length: METAL_COUNT }, (_, i) => {
    const n = String(i + 1).padStart(3, '0');
    return { id: `metal-${n}`, label: `Metal ${n}`, url: `/env-local/metal-${n}.jpg` };
  }),
];

export const ASSET_GROUPS: Record<string, AssetPreset[]> = {
  env: ENV_PRESETS,
};
