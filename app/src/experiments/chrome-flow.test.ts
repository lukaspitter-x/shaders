import { describe, expect, it } from 'vitest';
import chromeFlowSource from './chrome-flow.glsl?raw';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';

describe('chrome-flow.glsl', () => {
  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(chromeFlowSource))).toEqual([]);
  });

  it('groups controls into Surface / Environment / Material', () => {
    const { schema } = parseShader(chromeFlowSource);
    const sections = [...new Set(schema.map((c) => c.section).filter(Boolean))];
    expect(sections).toEqual(['Surface', 'Environment', 'Material']);
  });

  it('is a full-quad fill: resolution + time, no sdf', () => {
    const { system, defaults, schema } = parseShader(chromeFlowSource);
    expect(system.resolution).toBe('u_resolution');
    expect(system.time).toBe('u_time');
    expect(system.sdf).toBeUndefined();
    expect(schema.filter((c) => c.kind === 'color').map((c) => c.key)).toEqual([
      'u_tint',
      'u_warm',
    ]);
    expect(defaults.u_contrast).toBe(1.15);
    expect(defaults.u_flow).toBe(0.08);
  });
});
