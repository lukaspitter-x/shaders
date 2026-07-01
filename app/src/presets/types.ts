import type { ShaderValues } from '@/glsl/parse-annotations';

export interface Preset {
  id: string;
  name: string;
  createdAt: number;
  values: ShaderValues;
}

export interface ShaderPresets {
  shaderId: string;
  activePresetId: string;
  presets: Preset[];
  /** Uniform keys visible in Pencil's settings panel (empty = all hidden). */
  pencilKeys?: string[];
}

export type PresetStore = Record<string, ShaderPresets>;
