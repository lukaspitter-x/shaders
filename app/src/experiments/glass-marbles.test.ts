import { describe, expect, it } from 'vitest';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives, preparePencilExport } from '../glsl/strip-annotations';
import source from './glass-marbles.glsl?raw';
import { EXPERIMENTS } from './registry';

describe('glass-marbles.glsl', () => {
  it('is registered as a shape-optional fill that defaults to the circle host', () => {
    const experiment = EXPERIMENTS.find((item) => item.id === 'glass-marbles');
    const { system } = parseShader(source);

    expect(experiment).toMatchObject({
      label: 'Glass Marbles',
      type: 'fill',
      shapeOptional: true,
      defaultShapeId: 'circle',
      source,
    });
    // No @sdf: a per-pixel field lookup cost 12 ms/frame; the workbench
    // sizes the layer to the host shape instead (see decisions D11).
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
      expect(m[1]).toMatch(/^(\d+|[A-Z][A-Z_]+)$/);
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
      'Text Backdrop',
      'Glass',
      'Environment',
      'Focus',
      'Balls',
      'Motion',
      'Particles',
      'Palette',
    ]);
    expect(sections.get('Glass')).toEqual([
      'u_refraction',
      'u_aberration',
      'u_ripple',
      'u_rippleScale',
      'u_reflection',
      'u_reflectionFalloff',
      'u_fresnelColor',
      'u_fresnel',
      'u_fresnelWidth',
      'u_highlight',
      'u_lightAngle',
      'u_ballLens',
      'u_ballDensity',
      'u_ballHaze',
    ]);
    expect(sections.get('Motion')).toEqual([
      'u_speed',
      'u_swirl',
      'u_vortex',
      'u_bob',
      'u_turbulence',
      'u_spread',
      'u_tumble',
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

  it('fits the marble to the layer bounds so oval layers get oval marbles', () => {
    const { schema, defaults } = parseShader(source);
    const fit = schema.find((c) => c.key === 'u_fit');
    expect(fit?.kind).toBe('select');
    expect(fit?.section).toBe('Sphere');
    if (fit?.kind === 'select') expect(fit.options.map((o) => o.label)).toEqual(['Circle', 'Fill Shape']);
    expect(defaults.u_fit).toBe('0');
    expect(source).toContain('? (gl_FragCoord.xy - 0.5 * res) / (0.5 * res)');
  });

  it('lays a screen-space radial backdrop above the sphere for text', () => {
    const { schema, defaults } = parseShader(source);
    for (const key of ['u_backdropColor', 'u_backdropOpacity', 'u_backdropSize', 'u_backdropSoftness']) {
      expect(schema.find((c) => c.key === key)?.section).toBe('Text Backdrop');
    }
    expect(defaults.u_backdropOpacity).toBe(0);
    // Composited after tone mapping, right before output, so nothing renders over it.
    const idx = source.indexOf('color = mix(color, u_backdropColor, backdrop * u_backdropOpacity);');
    expect(idx).toBeGreaterThan(source.indexOf('color = toGamma(color);'));
    expect(idx).toBeLessThan(source.indexOf('gl_FragColor = vec4(mix(u_outside'));
  });

  it('emits hundreds of particles from the centre via a sector field', () => {
    const { schema } = parseShader(source);
    const count = schema.find((c) => c.key === 'u_particleCount');
    const speed = schema.find((c) => c.key === 'u_particleSpeed');
    expect(count?.section).toBe('Particles');
    expect(speed?.section).toBe('Particles');
    // Capacity = layers x sectors x slots, matching the Count dial's ceiling.
    const layers = Number(source.match(/const int P_LAYERS = (\d+);/)?.[1]);
    const perSector = Number(source.match(/const int P_PER_SECTOR = (\d+);/)?.[1]);
    const sectors = Number(source.match(/const float P_SECTORS = ([\d.]+);/)?.[1]);
    if (count?.kind === 'slider') expect(count.max).toBe(layers * sectors * perSector);
    // Straight flight from the centre, clamped inside the layer's disc.
    expect(source).toContain('float travel = min(eased * sc.reach, layerR * 0.985 - size);');
    // Fade out over the last Particle Fade of the life.
    expect(source).toContain('float fadeOut = 1.0 - smoothstep(1.0 - u_particleFade, 1.0, age);');
    // Hidden behind the nearest ball.
    expect(source).toContain('float tMax = near.index >= 0.0 ? near.t : 1e9;');
    // Visible from birth: the lookup widens up to four sectors either side
    // near the centre, and only the slot nominally at this radius (plus its
    // neighbours) is evaluated per sector.
    expect(source).toContain('float reachN = min(ceil(rbMax * P_SECTORS / (TAU * max(rho, 1e-4))), 4.0);');
    expect(source).toContain('float m1 = floor(mReal);');
    expect(schema.find((c) => c.key === 'u_particleFadeIn')?.section).toBe('Particles');
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
      expect(count.max).toBe(32);
      expect(count.step).toBe(1);
    }
    // The shader loop is sized to the slider's ceiling.
    expect(source).toContain('const int MAX_BALLS = 32;');
    // At most 16 balls are stored (a larger array falls out of registers on
    // Metal); the rest are recomputed inside the searches.
    expect(source).toContain('vec4 balls[HALF_BALLS];');
    expect(source).not.toMatch(/vec4\s+balls\[MAX_BALLS\]/);
    expect(source).toContain('vec4 b = ballAt(fi, t2, bigRadius, tilt);');
    expect(source).toContain('float t2 = t + min(h.t, 0.0);');
    // Second half of the search only when Count exceeds 16.
    expect(source).toContain('if (u_count > float(HALF_BALLS)) {');
    // Balls refract each other: the ball behind the nearest is found through its lens.
    expect(source).toContain('far = searchBalls(balls, lg.e, lg.rdOut, near.index, t + min(near.t, 0.0), bigRadius, tilt);');
    expect(source).toContain('vec3 shadeBallFar(');

    // No direct ball colours: one key colour + harmony is the only colour input.
    const colors = schema.filter((c) => c.kind === 'color').map((c) => c.key);
    expect(colors).toEqual([
      'u_outside',
      'u_backdropColor',
      'u_fresnelColor',
      'u_particleColor',
      'u_keyColor',
    ]);
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

  it('declares enough ring slots for the ball ceiling', () => {
    const axis = rings.filter(([rho]) => rho === 0).length;
    const orbit = rings.length - axis;
    expect(axis).toBe(3);
    expect(slots).toBe(6);
    expect(axis + orbit * slots).toBeGreaterThanOrEqual(32);
  });

  it('keeps the ring speed variation bounded (no runaway spin)', () => {
    // The angle integrates rate * (1 + 0.4 sin), so speed oscillates but
    // never grows with elapsed time.
    expect(source).toContain('float breathe = t - (0.4 / w) * cos(w * t + ringSeed * TAU);');
    expect(source).not.toMatch(/t \* rate \* \(1\.0 \+ wobble\)/);
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
