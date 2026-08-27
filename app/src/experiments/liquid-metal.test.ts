import { describe, expect, it } from 'vitest';
import source from './liquid-metal.glsl?raw';
import { EXPERIMENTS } from './registry';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';

describe('liquid-metal.glsl', () => {
  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(source))).toEqual([]);
  });

  it('uses an optional SDF alongside resolution and time', () => {
    const { system } = parseShader(source);
    const experiment = EXPERIMENTS.find((item) => item.id === 'liquid-metal');

    expect(system).toMatchObject({
      resolution: 'u_resolution',
      time: 'u_time',
      sdf: 'u_shape',
    });
    expect(experiment?.shapeOptional).toBe(true);
  });

  it('keeps the full-quad material visible when the SDF is empty', () => {
    expect(source).toContain('gl_FragColor = vec4(col, 1.0);');
    expect(lintPencil(source).some((finding) => finding.rule === 'sdf-gated-visibility')).toBe(
      false,
    );
  });

  it('exposes the reference material controls in stable sections', () => {
    const { schema, defaults } = parseShader(source);
    const sections = [...new Set(schema.map((control) => control.section).filter(Boolean))];

    expect(sections).toEqual([
      'Fluid Dynamics',
      'Shape',
      'Material',
      'Iridescence',
      'Environment',
    ]);
    expect(defaults).toMatchObject({
      u_scale: 3,
      u_shapeReactivity: 1,
      u_metalness: 0.82,
      u_iridescence: 0.9,
      u_ior: 1.45,
      u_thickness: 780,
    });
  });
});
