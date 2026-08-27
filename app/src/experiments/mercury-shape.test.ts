import { describe, expect, it } from 'vitest';
import { lintPencil } from '../glsl/lint-pencil';
import { parseShader } from '../glsl/parse-annotations';
import { downgradePencilDirectives } from '../glsl/strip-annotations';
import source from './mercury-shape.glsl?raw';
import { EXPERIMENTS } from './registry';

describe('mercury-shape.glsl', () => {
  it('is registered as a shape-dependent fill', () => {
    const experiment = EXPERIMENTS.find((item) => item.id === 'mercury-shape');
    const { system } = parseShader(source);

    expect(experiment).toMatchObject({
      label: 'Mercury Shape',
      type: 'fill',
      source,
    });
    expect(system).toMatchObject({
      resolution: 'u_resolution',
      time: 'u_time',
      sdf: 'u_shape',
    });
    expect(experiment?.shapeOptional).not.toBe(true);
  });

  it('exports lint-clean against the Pencil ES 1.00 rules', () => {
    expect(lintPencil(downgradePencilDirectives(source))).toEqual([]);
  });

  it('preserves the source controls and defaults', () => {
    const { schema, defaults } = parseShader(source);

    expect(schema.map((control) => control.key)).toEqual([
      'u_speed',
      'u_color1',
      'u_color2',
      'u_color3',
      'u_color4',
      'u_gradientAngle',
      'u_scale',
      'u_turbAmp',
      'u_turbFreq',
      'u_waveFreq',
      'u_edgeDistance',
      'u_reflection',
      'u_contourStrength',
    ]);
    expect(defaults).toEqual({
      u_speed: 0.5,
      u_color1: '#001417',
      u_color2: '#0d6b7a',
      u_color3: '#3bdcff',
      u_color4: '#d9f7ff',
      u_gradientAngle: 45,
      u_scale: 1.8,
      u_turbAmp: 0.48,
      u_turbFreq: 1.4,
      u_waveFreq: 1.6,
      u_edgeDistance: 0.03,
      u_reflection: 0.5,
      u_contourStrength: 0.6,
    });
  });
});
