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

describe('gradient.glsl', () => {
  it('is lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(gradientSource)).toEqual([]);
  });

  it('exposes the gradient type as a paste-safe 0–4 slider (no @select)', () => {
    expect(gradientSource).not.toContain('@select');
    expect(gradientSource).not.toContain('@switch');
    const { schema } = parseShader(gradientSource);
    const type = schema.find((c) => c.key === 'u_type');
    expect(type?.kind).toBe('slider');
    if (type?.kind === 'slider') {
      expect(type.min).toBe(0);
      expect(type.max).toBe(4);
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
    expect(defaults.u_type).toBe(0);
    expect(typeof defaults.u_key).toBe('string');
  });
});
