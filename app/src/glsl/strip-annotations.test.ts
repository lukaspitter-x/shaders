import { describe, it, expect } from 'vitest';
import { stripHiddenAnnotations } from './strip-annotations';

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
});
