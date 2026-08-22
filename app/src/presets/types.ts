import type { ShaderValues } from '@/glsl/parse-annotations';

/** Workbench host-shape settings that travel with a shader preset. */
export interface PresetShape {
  id: string;
  size: number;
}

export interface Preset {
  id: string;
  name: string;
  createdAt: number;
  values: ShaderValues;
  /** Optional for backwards compatibility with presets saved before host shapes were included. */
  shape?: PresetShape;
}

export interface ShaderPresets {
  shaderId: string;
  activePresetId: string;
  presets: Preset[];
  /** Uniform keys visible in Pencil's settings panel (empty = all hidden). */
  pencilKeys?: string[];
}

export type PresetStore = Record<string, ShaderPresets>;
