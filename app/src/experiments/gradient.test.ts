/**
 * Gradient experiment — contract tests. The shader is data (annotated GLSL),
 * so the testable surface is: (1) it stays inside Pencil's ES 1.00 envelope
 * (lint clean), and (2) its annotations parse into the settings schema the
 * panel is designed around (type selector, single key color, sections).
 */
import { describe, expect, it } from 'vitest';
import gradientSource from './gradient.glsl?raw';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';

describe('gradient.glsl', () => {
  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(gradientSource))).toEqual([]);
  });

  it('exposes the five gradient types as a select', () => {
    const { schema } = parseShader(gradientSource);
    const type = schema.find((c) => c.key === 'u_type');
    expect(type?.kind).toBe('select');
    if (type?.kind === 'select') {
      expect(type.options.map((o) => o.label)).toEqual([
        'Linear',
        'Radial',
        'Hole',
        'Mesh',
        'Sky',
      ]);
    }
  });

  it('derives everything from a single key color (exactly one color control)', () => {
    const { schema } = parseShader(gradientSource);
    const colors = schema.filter((c) => c.kind === 'color');
    expect(colors.map((c) => c.key)).toEqual(['u_key']);
  });

  it('groups controls into the expected sections', () => {
    const { schema } = parseShader(gradientSource);
    const sections = [...new Set(schema.map((c) => c.section).filter(Boolean))];
    expect(sections).toEqual([
      'Type',
      'Color',
      'Accent',
      'Shape',
      'Hole',
      'Mesh',
      'Sky',
      'Finish',
    ]);
  });

  it('declares resolution as its only system uniform and sane defaults', () => {
    const { system, defaults } = parseShader(gradientSource);
    expect(system.resolution).toBe('u_resolution');
    expect(system.time).toBeUndefined();
    expect(system.sdf).toBeUndefined();
    expect(defaults.u_type).toBe('0');
    expect(typeof defaults.u_key).toBe('string');
  });
});
