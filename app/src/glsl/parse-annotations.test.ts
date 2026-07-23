import { describe, expect, it } from 'vitest';
import { parseShader, sanitizeValues } from './parse-annotations';

const SOURCE = `
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @mouse */
uniform vec2 u_mouse;

/**
 * Overall motion speed.
 * @label Speed
 * @default 0.4
 * @range 0, 2
 */
uniform float u_speed;

/** @label Color A @color @default #06121f */
uniform vec3 u_colorA;

/** @sdf */
uniform sampler2D u_shape;

/** @label Background */
uniform sampler2D u_image;
`;

describe('parseShader', () => {
  const parsed = parseShader(SOURCE);

  it('maps system uniforms by role to their names', () => {
    expect(parsed.system).toEqual({
      resolution: 'u_resolution',
      time: 'u_time',
      mouse: 'u_mouse',
      sdf: 'u_shape',
    });
  });

  it('keeps system uniforms out of the control schema', () => {
    const keys = parsed.schema.map((c) => c.key);
    expect(keys).toEqual(['u_speed', 'u_colorA', 'u_image']);
  });

  it('turns a labelled sampler2D into an image control', () => {
    const img = parsed.schema.find((c) => c.key === 'u_image');
    expect(img).toMatchObject({ kind: 'image', label: 'Background' });
    expect(parsed.defaults.u_image).toBe('');
    expect(parsed.images).toEqual(['u_image']);
  });

  it('turns a ranged float into a slider with label, hint, and bounds', () => {
    const speed = parsed.schema.find((c) => c.key === 'u_speed');
    expect(speed).toMatchObject({ kind: 'slider', label: 'Speed', min: 0, max: 2 });
    expect((speed as { hint?: string }).hint).toBe('Overall motion speed.');
    expect(parsed.defaults.u_speed).toBe(0.4);
  });

  it('turns a @color vec3 into a color control with a normalized hex default', () => {
    const color = parsed.schema.find((c) => c.key === 'u_colorA');
    expect(color).toMatchObject({ kind: 'color', label: 'Color A' });
    expect(parsed.defaults.u_colorA).toBe('#06121f');
  });

  it('groups controls via a `// SECTION:` line comment (Pencil-invisible)', () => {
    const src = `
// SECTION: Look
/** @label A @default 1 @range 0, 2 */
uniform float u_a;

// SECTION: Look
/** @label B @default 1 @range 0, 2 */
uniform float u_b;

// SECTION: Motion
/** @label C @default 1 @range 0, 2 */
uniform float u_c;

/** @label D @default 1 @range 0, 2 */
uniform float u_d;`;
    const { schema } = parseShader(src);
    const byKey = (k: string) => schema.find((c) => c.key === k) as { section?: string };
    expect(byKey('u_a').section).toBe('Look');
    expect(byKey('u_b').section).toBe('Look');
    expect(byKey('u_c').section).toBe('Motion');
    // A uniform with no preceding marker stays ungrouped.
    expect(byKey('u_d').section).toBeUndefined();
  });
});

describe('sanitizeValues', () => {
  const parsed = parseShader(SOURCE);

  it('clamps a slider value to its range', () => {
    expect(sanitizeValues(parsed.schema, { u_speed: 99 }).u_speed).toBe(2);
    expect(sanitizeValues(parsed.schema, { u_speed: -5 }).u_speed).toBe(0);
  });

  it('leaves in-range numbers and colors untouched', () => {
    const out = sanitizeValues(parsed.schema, { u_speed: 1.3, u_colorA: '#abcdef' });
    expect(out.u_speed).toBe(1.3);
    expect(out.u_colorA).toBe('#abcdef');
  });

  it('coerces numeric strings and ignores non-finite values', () => {
    expect(sanitizeValues(parsed.schema, { u_speed: '1.5' }).u_speed).toBe(1.5);
    expect(sanitizeValues(parsed.schema, { u_speed: 'nope' }).u_speed).toBe('nope');
  });

  describe('select controls', () => {
    // A control that changed kind from slider to select leaves stale NUMERIC
    // values in stored presets — sanitize must coerce them to option strings.
    const selectSource = `
/** @label Type @select Linear, Radial, Hole, Mesh, Sky @default 0 */
uniform float u_type;
`;
    const { schema } = parseShader(selectSource);

    it('coerces a stale numeric value to its option string', () => {
      expect(sanitizeValues(schema, { u_type: 3 }).u_type).toBe('3');
      expect(sanitizeValues(schema, { u_type: 0 }).u_type).toBe('0');
    });

    it('rounds and clamps out-of-range values to a valid option', () => {
      expect(sanitizeValues(schema, { u_type: 2.4 }).u_type).toBe('2');
      expect(sanitizeValues(schema, { u_type: 99 }).u_type).toBe('4');
      expect(sanitizeValues(schema, { u_type: -1 }).u_type).toBe('0');
    });

    it('passes valid option strings through untouched', () => {
      expect(sanitizeValues(schema, { u_type: '2' }).u_type).toBe('2');
    });
  });
});
