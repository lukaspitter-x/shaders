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
    const result = stripHiddenAnnotations(src, new Set());
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
    const result = stripHiddenAnnotations(src, new Set(['u_speed']));
    expect(result).toContain('/** @label Speed');
    expect(result).toContain('uniform float u_speed;');
  });

  it('replaces hidden float uniform with #define using @default', () => {
    const src = [
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set());
    expect(result).not.toContain('uniform float u_speed');
    expect(result).toContain('#define u_speed 0.4');
  });

  it('replaces hidden float with 0.0 when no @default', () => {
    const src = [
      '/** @label Foo */',
      'uniform float u_foo;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set());
    expect(result).toContain('#define u_foo 0.0');
  });

  it('replaces hidden color vec3 with rgb values', () => {
    const src = [
      '/** @label Key Color @color @default #1f6bff */',
      'uniform vec3 u_key;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set());
    expect(result).toContain('#define u_key vec3(');
    expect(result).not.toContain('uniform vec3 u_key');
  });

  it('strips SECTION marker for hidden uniforms', () => {
    const src = [
      '// SECTION: Light',
      '/** @label Speed @default 0.4 @range 0, 2 */',
      'uniform float u_speed;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set());
    expect(result).not.toContain('SECTION');
    expect(result).toContain('#define u_speed 0.4');
  });

  it('preserves @sdf system uniform', () => {
    const src = [
      '/** @sdf */',
      'uniform sampler2D u_sdf;',
    ].join('\n');
    const result = stripHiddenAnnotations(src, new Set());
    expect(result).toContain('/** @sdf */');
    expect(result).toContain('uniform sampler2D u_sdf;');
  });
});
