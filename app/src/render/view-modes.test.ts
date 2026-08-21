import { describe, expect, it } from 'vitest';
import chromeSource from '@/experiments/chrome.glsl?raw';
import { parseShader } from '@/glsl/parse-annotations';
import {
  ENV_VIEW_PARSED,
  ENV_VIEW_UNIFORMS,
  SDF_VIEW_PARSED,
  envPreviewAvailable,
} from './view-modes';

describe('view modes', () => {
  it('sdf view parses with an @sdf system uniform', () => {
    expect(SDF_VIEW_PARSED.system.sdf).toBe('u_shape');
    expect(SDF_VIEW_PARSED.system.resolution).toBe('u_resolution');
  });

  it('env view declares exactly the uniforms it reads', () => {
    const names = new Set(ENV_VIEW_PARSED.uniforms.map((u) => u.name));
    for (const n of ENV_VIEW_UNIFORMS) expect(names.has(n)).toBe(true);
  });

  // Sync guard: if chrome.glsl renames an env dial, this fails and the env
  // view math must be updated to match (they mirror each other by hand).
  it('chrome.glsl exposes every uniform the env view reads', () => {
    expect(envPreviewAvailable(parseShader(chromeSource))).toBe(true);
  });

  it('env view is unavailable for shaders without the env dials', () => {
    const minimal = parseShader(
      ['/** @resolution */', 'uniform vec2 u_resolution;'].join('\n'),
    );
    expect(envPreviewAvailable(minimal)).toBe(false);
  });
});
