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

    expect([...sections.keys()]).toEqual([
      'Sphere',
      'Glass',
      'Environment',
      'Focus',
      'Balls',
      'Motion',
      'Palette',
    ]);
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

  it('grows out-of-focus balls by a circle of confusion and fades their edge', () => {
    const { schema, defaults } = parseShader(source);
    expect(schema.find((c) => c.key === 'u_bokeh')?.section).toBe('Focus');
    expect(schema.find((c) => c.key === 'u_focus')?.section).toBe('Focus');
    expect(schema.find((c) => c.key === 'u_backBlur')?.section).toBe('Focus');
    // Behind the focus plane the circle of confusion is scaled by Back Blur.
    expect(source).toContain('float amount = d < 0.0 ? -d * u_backBlur : d;');
    expect(defaults.u_focus).toBe(0.5);
    expect(source).toContain('b.w += defocus(b.z, bigRadius);');
    expect(source).toContain('float cover = 1.0 - smoothstep(trueR - blur, trueR + blur, dist);');
    expect(source).toContain('return mix(behind, result, cover);');
  });

  it('exposes an equirectangular environment map with bundled presets', () => {
    const { schema, images } = parseShader(source);
    const env = schema.find((c) => c.key === 'u_env');
    expect(images).toEqual(['u_env']);
    expect(env?.kind).toBe('image');
    expect(env?.section).toBe('Environment');
    if (env?.kind === 'image') expect(env.assets).toBe('env');
    for (const key of ['u_envMix', 'u_envThrough', 'u_envRotation', 'u_studioDetail']) {
      expect(schema.find((c) => c.key === key)?.section).toBe('Environment');
    }
    // One sampler only, so textureSize is never needed and never used.
    expect(source).not.toContain('textureSize');
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
      expect(count.max).toBe(16);
      expect(count.step).toBe(1);
    }
    // The shader loop is sized to the slider's ceiling.
    expect(source).toContain('const int MAX_BALLS = 16;');

    // No direct ball colours: one key colour + harmony is the only colour input.
    const colors = schema.filter((c) => c.kind === 'color').map((c) => c.key);
    expect(colors).toEqual(['u_outside', 'u_keyColor']);
    expect(defaults.u_keyColor).toBe('#ea5a78');
    expect(schema.find((c) => c.key === 'u_baseHue')).toBeUndefined();
  });
});

describe('glass-marbles.glsl ball slots', () => {
  // Mirror of the ring table: balls may never intersect because every slot's
  // envelope (a sphere of radius `room` around the slot point) is disjoint
  // from every other. Extracted from the shader so the two cannot drift.
  const rings = [...source.matchAll(/const vec3 RING_\w+ = vec3\(([^)]+)\);/g)].map((m) =>
    m[1].split(',').map((v) => Number(v.trim())),
  );
  const slots = Number(source.match(/const float RING_SLOTS = ([\d.]+);/)?.[1]);

  it('declares six rings and a slot count', () => {
    expect(rings).toHaveLength(6);
    expect(slots).toBe(5);
    // 3 axis slots + 3 rings x 5 slots must cover the ball ceiling.
    expect(3 + 3 * slots).toBeGreaterThanOrEqual(16);
  });

  it('keeps every ring envelope inside the unit flock sphere', () => {
    for (const [rho, y, room] of rings) {
      expect(Math.hypot(rho, y) + room).toBeLessThanOrEqual(1);
    }
  });

  it('keeps ring envelopes apart from each other', () => {
    for (let a = 0; a < rings.length; a++) {
      for (let b = a + 1; b < rings.length; b++) {
        const [ra, ya, rooma] = rings[a];
        const [rb, yb, roomb] = rings[b];
        expect(Math.hypot(ra - rb, ya - yb)).toBeGreaterThanOrEqual(rooma + roomb);
      }
    }
  });

  it('keeps neighbouring slots on a ring apart', () => {
    for (const [rho, , room] of rings) {
      if (rho === 0) continue; // axis balls are single slots
      const chord = 2 * rho * Math.sin(Math.PI / slots);
      expect(chord).toBeGreaterThanOrEqual(2 * room);
    }
  });

  it('never lets a ball leave its envelope', () => {
    // radius = room * size * variation ≤ room; wander ≤ (room - radius) * 0.95.
    expect(source).toContain(
      'float radius = room * axisShrink * u_ballSize * mix(1.0, mix(0.45, 1.0, h.w), u_sizeVariation);',
    );
    expect(source).toContain('float axisShrink = rho < 0.01 ? 0.72 : 1.0;');
    expect(source).toContain('wander /= max(1.0, length(wander));');
    expect(source).toContain('pos += wander * (room - radius) * 0.95;');
  });
});
