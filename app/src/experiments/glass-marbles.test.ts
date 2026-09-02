import { describe, expect, it } from 'vitest';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives, preparePencilExport } from '../glsl/strip-annotations';
import source from './glass-marbles.glsl?raw';
import { EXPERIMENTS } from './registry';

describe('glass-marbles.glsl', () => {
  it('is registered as a full-quad fill with no shape dependency', () => {
    const experiment = EXPERIMENTS.find((item) => item.id === 'glass-marbles');
    const { system } = parseShader(source);

    expect(experiment).toMatchObject({ label: 'Glass Marbles', type: 'fill', source });
    expect(system).toEqual({ resolution: 'u_resolution', time: 'u_time' });
  });

  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(source))).toEqual([]);
    const parsed = parseShader(source);
    const exported = preparePencilExport(source, new Set(), parsed.defaults);
    expect(lintPencil(exported).filter((f) => f.severity === 'error')).toEqual([]);
  });

  it('avoids GLSL constructs Pencil cannot compile', () => {
    // No recursion (GLSL forbids it) and no `out` used as an identifier.
    expect(source).not.toMatch(/\bvec3\s+out\b/);
    const nearBody = source.slice(source.indexOf('vec3 traceChannel('));
    expect(nearBody.slice(0, nearBody.indexOf('\n}\n'))).not.toMatch(/\{[\s\S]*traceChannel\(/);
    // Every loop bound is a compile-time constant.
    for (const m of source.matchAll(/for\s*\([^;]*;\s*\w+\s*<\s*(\w+)/g)) {
      expect(m[1]).toMatch(/^(\d+|MAX_BALLS)$/);
    }
  });

  it('groups the dials into Sphere, Glass, Balls, Motion and Palette sections', () => {
    const { schema } = parseShader(source);
    const sections = new Map<string, string[]>();
    for (const control of schema) {
      const list = sections.get(control.section ?? '') ?? [];
      list.push(control.key);
      sections.set(control.section ?? '', list);
    }

    expect([...sections.keys()]).toEqual(['Sphere', 'Glass', 'Balls', 'Motion', 'Palette']);
    expect(sections.get('Glass')).toEqual([
      'u_refraction',
      'u_aberration',
      'u_ripple',
      'u_rippleScale',
      'u_reflection',
      'u_highlight',
      'u_lightAngle',
      'u_ballLens',
      'u_ballDensity',
    ]);
    expect(sections.get('Motion')).toEqual([
      'u_speed',
      'u_swirl',
      'u_vortex',
      'u_bob',
      'u_turbulence',
      'u_spread',
      'u_tilt',
    ]);
  });

  it('derives colours from a harmony scheme plus randomisable seeds', () => {
    const { schema, defaults } = parseShader(source);
    const harmony = schema.find((c) => c.key === 'u_harmony');
    const bgHue = schema.find((c) => c.key === 'u_bgHueMode');
    const colorSeed = schema.find((c) => c.key === 'u_colorSeed');
    const layoutSeed = schema.find((c) => c.key === 'u_layoutSeed');
    const count = schema.find((c) => c.key === 'u_count');

    expect(harmony?.kind).toBe('select');
    if (harmony?.kind === 'select') {
      expect(harmony.options.map((o) => o.label)).toEqual([
        'Analogous',
        'Complementary',
        'Split Complementary',
        'Triadic',
        'Tetradic',
        'Monochrome',
      ]);
    }
    expect(defaults.u_harmony).toBe('3');

    expect(bgHue?.kind).toBe('select');
    if (bgHue?.kind === 'select') {
      expect(bgHue.options.map((o) => o.label)).toEqual(['Base', 'Complement', 'Random']);
    }

    for (const seed of [colorSeed, layoutSeed]) {
      expect(seed?.kind).toBe('slider');
      if (seed?.kind === 'slider') {
        expect(seed.min).toBe(0);
        expect(seed.max).toBe(100);
        expect(seed.step).toBe(1);
      }
    }

    expect(count?.kind).toBe('slider');
    if (count?.kind === 'slider') {
      expect(count.min).toBe(1);
      expect(count.max).toBe(24);
      expect(count.step).toBe(1);
    }
    // The shader loop is sized to the slider's ceiling.
    expect(source).toContain('const int MAX_BALLS = 24;');

    // No direct ball colours: harmony + base hue is the only colour input.
    const colors = schema.filter((c) => c.kind === 'color').map((c) => c.key);
    expect(colors).toEqual(['u_outside']);
  });
});
