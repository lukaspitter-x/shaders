/**
 * Chrome Tiles — contract tests. The shader is data (annotated GLSL), so the
 * testable surface is: it stays inside Pencil's ES 1.00 envelope, and its
 * annotations parse into the panel schema (primitive selector, four-color
 * palette from the source pen, sections).
 */
import { describe, expect, it } from 'vitest';
import source from './chrome-tiles.glsl?raw';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';

describe('chrome-tiles.glsl', () => {
  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(source))).toEqual([]);
  });

  it('exposes every primitive family plus a mixed mode as a select', () => {
    const { schema } = parseShader(source);
    const shapes = schema.find((c) => c.key === 'u_shapeSet');
    expect(shapes?.kind).toBe('select');
    if (shapes?.kind === 'select') {
      expect(shapes.options.map((o) => o.label)).toEqual([
        'Mixed',
        'Tubes',
        'Rings',
        'Domes',
        'Boxes',
        'Pyramids',
        'Half-Pipes',
        'Plates',
      ]);
    }
  });

  it("keeps the source pen's four-color palette", () => {
    const { schema, defaults } = parseShader(source);
    const colors = schema.filter((c) => c.kind === 'color').map((c) => c.key);
    expect(colors).toEqual(['u_color1', 'u_color2', 'u_color3', 'u_color4']);
    expect(defaults.u_color1).toBe('#ffffff');
    expect(defaults.u_color2).toBe('#ffafaf');
    expect(defaults.u_color3).toBe('#0099ff');
    expect(defaults.u_color4).toBe('#aaffff');
  });

  it('groups controls into the expected sections', () => {
    const { schema } = parseShader(source);
    const sections = [...new Set(schema.map((c) => c.section).filter(Boolean))];
    expect(sections).toEqual(['Tiling', 'Relief', 'Palette', 'Environment', 'Lighting']);
  });

  it('is a full-quad fill: resolution + time, no @sdf gating', () => {
    const { system } = parseShader(source);
    expect(system.resolution).toBe('u_resolution');
    expect(system.time).toBe('u_time');
    expect(system.sdf).toBeUndefined();
  });
});
