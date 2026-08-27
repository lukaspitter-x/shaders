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
    expect(experiment?.defaultShapeId).toBe('rounded-rect');
  });

  it('keeps the full-quad material visible when the SDF is empty', () => {
    expect(source).toContain('gl_FragColor = vec4(color, 1.0);');
    expect(lintPencil(source).some((finding) => finding.rule === 'sdf-gated-visibility')).toBe(
      false,
    );
  });

  it('matches the source material controls and defaults', () => {
    const { schema, defaults } = parseShader(source);
    const sections = [...new Set(schema.map((control) => control.section).filter(Boolean))];

    expect(sections).toEqual(['Fluid Dynamics', 'Iridescence (Rainbow)', 'Base Material']);
    expect(defaults).toMatchObject({
      u_scale: 0.00298,
      u_shapeReactivity: 1,
      u_distortion: 1.52,
      u_edgeProtection: 1,
      u_speed: 0,
      u_twistSpeed: 1,
      u_linearMix: 0,
      u_linearDirection: 0,
      u_linearDensity: 1,
      u_iridescence: 0.907,
      u_rainbowBoost: 0.25,
      u_iridescenceIOR: 1,
      u_thicknessMin: 759,
      u_thicknessMax: 800,
      u_roughness: 0.452,
      u_metalness: 0.587,
      u_clearcoat: 0.071,
    });
  });

  it('retains the source domain-warp and analytical-normal constants', () => {
    expect(source).toContain('vec3 warpedP = p + warp * 1.5;');
    expect(source).toContain('float eps = 0.03;');
    expect(source).toContain('normalize(vec3(nx - n0, ny - n0, nz - n0))');
    expect(source).toContain('smoothDist * u_shapeReactivity * 150.0 * u_scale');
  });

  it('separates twist animation from contour flow and preserves ripple by default', () => {
    expect(source).toContain('float twistTime = u_time * u_twistSpeed;');
    expect(source).toContain('p.xy += contourTangent * (u_time * u_speed * 0.5);');
    expect(source).toContain('vec3 noiseNormal = mix(rippleNormal, linearNormal, linearMix);');
    expect(source).toContain('float patternNoise = mix(n0, l0, linearMix);');
  });

  it('can amplify thin-film color without changing the thickness phase', () => {
    expect(source).toContain('vec3 rainbow = clamp(film / filmLuminance, 0.15, 2.5);');
    expect(source).toContain('u_iridescence * u_rainbowBoost');
    expect(source).toContain('0.08 + grazingResponse * 0.92');
  });
});
