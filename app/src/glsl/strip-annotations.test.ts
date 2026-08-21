import { describe, it, expect } from 'vitest';
import { bakeDefaults, downgradePencilDirectives, stripHiddenAnnotations } from './strip-annotations';
import { lintPencil } from './lint-pencil';

describe('bakeDefaults', () => {
  it('rewrites a float @default with the current value', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = bakeDefaults(src, { u_speed: 1.25 });
    expect(result).toContain('@default 1.25 ');
    expect(result).not.toContain('@default 0.4');
    expect(result).toContain('@range 0, 2');
    expect(result).toContain('uniform float u_speed;');
  });

  it('rewrites a color @default with the current hex', () => {
    const src = [
      '/** @label Tint @color @default #4466ff */',
      'uniform vec3 u_tint;',
    ].join('\n');
    const result = bakeDefaults(src, { u_tint: '#ff8800' });
    expect(result).toContain('@default #ff8800');
    expect(result).not.toContain('#4466ff');
  });

  it('rewrites a multi-line doc block without breaking its layout', () => {
    const src = [
      '/**',
      ' * How deep the bevel goes.',
      ' * @label Depth',
      ' * @default 14',
      ' * @range 1, 80',
      ' */',
      'uniform float u_depth;',
    ].join('\n');
    const result = bakeDefaults(src, { u_depth: 32 });
    expect(result).toContain(' * @default 32.0');
    expect(result).toContain(' * @range 1, 80');
    expect(result).toContain('uniform float u_depth;');
  });

  it('inserts @default when the doc block has none', () => {
    const src = [
      '/** @label Speed @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = bakeDefaults(src, { u_speed: 0.5 });
    expect(result).toContain('@default 0.5');
  });

  it('leaves system uniforms untouched', () => {
    const src = ['/** @resolution */', 'uniform vec2 u_resolution;'].join('\n');
    expect(bakeDefaults(src, { u_resolution: 3 })).toBe(src);
  });

  it('leaves uniforms without a current value untouched', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    expect(bakeDefaults(src, {})).toBe(src);
  });

  it('skips image samplers (blob URL values are not bakeable)', () => {
    const src = ['/** @label Env Image */', 'uniform sampler2D u_env;'].join('\n');
    expect(bakeDefaults(src, { u_env: 'blob:http://x/123' })).toBe(src);
  });

  it('bakes switch booleans as true/false', () => {
    const src = [
      '/** @label Invert @switch @default false */',
      'uniform float u_invert;',
    ].join('\n');
    const result = bakeDefaults(src, { u_invert: true });
    expect(result).toContain('@default true');
  });

  it('bakes select string values as numbers', () => {
    const src = [
      '/** @label Mode @select A, B, C @default 0 */',
      'uniform float u_mode;',
    ].join('\n');
    const result = bakeDefaults(src, { u_mode: '2' });
    expect(result).toContain('@default 2.0');
  });

  it('bakes bezier arrays as a comma list', () => {
    const src = [
      '/** @label Ease @bezier @default 0.25, 0.1, 0.25, 1.0 */',
      'uniform vec4 u_ease;',
    ].join('\n');
    const result = bakeDefaults(src, { u_ease: [0.5, 0, 1, 1] });
    expect(result).toContain('@default 0.5, 0.0, 1.0, 1.0');
  });

  it('downgrade strips the workbench-only @assets directive', () => {
    const src = [
      '/**',
      ' * Env image.',
      ' * @label Env Image',
      ' * @assets env',
      ' */',
      'uniform sampler2D u_env;',
    ].join('\n');
    const result = downgradePencilDirectives(src);
    expect(result).not.toContain('@assets');
    expect(result).toContain('@label Env Image');
    expect(result).toContain('uniform sampler2D u_env;');
  });

  it('baked output then export path still lints clean', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
      'void main() { gl_FragColor = vec4(u_speed); }',
    ].join('\n');
    const exported = downgradePencilDirectives(bakeDefaults(src, { u_speed: 1.5 }));
    expect(lintPencil(exported)).toEqual([]);
  });
});

describe('stripHiddenAnnotations', () => {
  it('preserves system uniforms regardless of visibleKeys', () => {
    const src = [
      '/** @resolution */',
      'uniform vec2 u_resolution;',
      '/** @time */',
      'uniform float u_time;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), {});
    expect(result).toContain('/** @resolution */');
    expect(result).toContain('uniform vec2 u_resolution;');
    expect(result).toContain('/** @time */');
    expect(result).toContain('uniform float u_time;');
  });

  it('keeps visible user uniforms with their full doc block', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(['u_speed']), { u_speed: 0.8 });
    expect(result).toContain('/** @label Speed');
    expect(result).toContain('uniform float u_speed;');
  });

  it('uses current value for hidden float, not @default', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), { u_speed: 1.7 });
    expect(result).not.toContain('uniform float u_speed');
    expect(result).toContain('#define u_speed 1.7');
  });

  it('falls back to @default when no current value', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), {});
    expect(result).toContain('#define u_speed 0.4');
  });

  it('replaces hidden float with 0.0 when no @default and no value', () => {
    const src = [
      '/** @label Foo */',
      'uniform float u_foo;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), {});
    expect(result).toContain('#define u_foo 0.0');
  });

  it('uses current hex color value for hidden vec3', () => {
    const src = [
      '/** @label Key Color @color @default #1f6bff */',
      'uniform vec3 u_key;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), { u_key: '#ff0000' });
    expect(result).toContain('#define u_key vec3(1.0000, 0.0000, 0.0000)');
    expect(result).not.toContain('uniform vec3 u_key');
  });

  it('strips SECTION marker for hidden uniforms', () => {
    const src = [
      '// SECTION: Light',
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), { u_speed: 0.9 });
    expect(result).not.toContain('SECTION');
    expect(result).toContain('#define u_speed 0.9');
  });

  it('preserves @sdf system uniform', () => {
    const src = [
      '/** @sdf */',
      'uniform sampler2D u_sdf;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), {});
    expect(result).toContain('/** @sdf */');
    expect(result).toContain('uniform sampler2D u_sdf;');
  });

  it('inlines a hidden @select using its current (string) value', () => {
    const src = [
      '/** @label Type @select Linear, Radial, Hole @default 0 */',
      'uniform float u_type;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(), { u_type: '2' });
    expect(result).toContain('#define u_type 2.0');
    expect(result).not.toContain('uniform float u_type');
  });
});

describe('downgradePencilDirectives', () => {
  it('rewrites a visible @select into a paste-safe @range with an option-map comment', () => {
    const src = [
      '/**',
      ' * Which construction to render.',
      ' * @label Type',
      ' * @select Linear, Radial, Hole, Mesh, Sky',
      ' * @default 0',
      ' */',
      'uniform float u_type;',
    ].join('\n');
    const result = downgradePencilDirectives(src);
    expect(result).not.toContain('@select');
    expect(result).toContain('@range 0, 4');
    expect(result).toContain('@default 0');
    // Option map survives as a Pencil-ignored line comment.
    expect(result).toContain('// u_type: 0 Linear · 1 Radial · 2 Hole · 3 Mesh · 4 Sky');
  });

  it('rewrites @switch into @range 0, 1 and numifies boolean defaults', () => {
    const src = [
      '/** @label Flip @switch @default true */',
      'uniform float u_flip;',
    ].join('\n');
    const result = downgradePencilDirectives(src);
    expect(result).not.toContain('@switch');
    expect(result).toContain('@range 0, 1');
    expect(result).toContain('@default 1');
    expect(result).not.toContain('@default true');
  });

  it('drops @step and leaves confirmed directives untouched', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 @step 0.1 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = downgradePencilDirectives(src);
    expect(result).not.toContain('@step');
    expect(result).toContain('@range 0, 2');
    expect(result).toContain('@default 0.4');
  });

  it('produces lint-clean output for a shader using workbench-only directives', () => {
    const src = [
      '/** @resolution */',
      'uniform vec2 u_resolution;',
      '/** @label Type @select A, B, C @default 0 */',
      'uniform float u_type;',
      '/** @label Flip @switch @default false */',
      'uniform float u_flip;',
      'void main() { gl_FragColor = vec4(u_type, u_flip, 0.0, 1.0); }',
    ].join('\n');
    expect(lintPencil(downgradePencilDirectives(src))).toEqual([]);
  });

  it('is applied to visible uniforms during export', () => {
    const src = [
      '/** @label Type @select A, B, C @default 0 */',
      'uniform float u_type;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set(['u_type']), { u_type: '1' });
    expect(result).not.toContain('@select');
    expect(result).toContain('@range 0, 2');
    expect(result).toContain('uniform float u_type;');
  });
});
