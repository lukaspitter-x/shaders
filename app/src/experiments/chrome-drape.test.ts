/**
 * Chrome Drape experiment — contract tests: lint-clean for Pencil, and the
 * annotations parse into the intended panel (sections, three material
 * colors, time-driven).
 */
import { describe, expect, it } from 'vitest';
import source from './chrome-drape.glsl?raw';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';

describe('chrome-drape.glsl', () => {
  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(source))).toEqual([]);
  });

  it('groups controls into the expected sections', () => {
    const { schema } = parseShader(source);
    const sections = [...new Set(schema.map((c) => c.section).filter(Boolean))];
    expect(sections).toEqual(['Folds', 'Motion', 'Material', 'Light', 'Finish']);
  });

  it('exposes tint, shadow and highlight as its color controls', () => {
    const { schema } = parseShader(source);
    const colors = schema.filter((c) => c.kind === 'color').map((c) => c.key);
    expect(colors).toEqual(['u_tint', 'u_shadow', 'u_highlight']);
  });

  it('declares resolution + time and no sdf', () => {
    const { system } = parseShader(source);
    expect(system.resolution).toBe('u_resolution');
    expect(system.time).toBe('u_time');
    expect(system.sdf).toBeUndefined();
  });
});
