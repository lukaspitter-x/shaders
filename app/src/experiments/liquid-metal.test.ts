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

    expect(sections).toEqual([
      'Fluid Dynamics',
      'Shape Geometry',
      'Iridescence (Rainbow)',
      'Base Material',
    ]);
    expect(defaults).toMatchObject({
      u_scale: 0.00298,
      u_shapeReactivity: 1,
      u_shapeDepth: 1,
      u_bevelWidth: 30,
      u_bevelProfile: 1,
      u_shoulder: 0,
      u_distortion: 1.52,
      u_edgeProtection: 1,
      u_speed: 0,
      u_twistSpeed: 1,
      u_linearMix: 0,
      u_linearDirection: 0,
      u_stripeCount: '0',
      u_linearDensity: 1,
      u_linearScale: 0,
      u_linearBandWidth: 0.5,
      u_linearStripeWidth: 0.5,
      u_stripeSharpness: 0,
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

  it('offers density spacing plus exact one, two, and three stripe modes', () => {
    const { schema } = parseShader(source);
    const count = schema.find((control) => control.key === 'u_stripeCount');

    expect(count).toMatchObject({
      kind: 'select',
      label: 'Stripe Count',
      options: [
        { label: 'Density', value: '0' },
        { label: 'One', value: '1' },
        { label: 'Two', value: '2' },
        { label: 'Three', value: '3' },
      ],
    });
    expect(source).toContain('float exactCount = max(floor(u_stripeCount + 0.5), 1.0);');
    expect(source).toContain('float exactCycle = normalizedProjection * exactCount;');
    expect(source).toContain('u_stripeCount < 0.5 ? densityCycle : exactCycle');
  });

  it('keeps stripe width and gap regular, complementary, and non-overlapping', () => {
    expect(source).toContain('float stripeWeight = clamp(u_linearBandWidth, 0.05, 0.95);');
    expect(source).toContain('float gapWeight = clamp(u_linearStripeWidth, 0.05, 0.95);');
    expect(source).toContain('stripeWeight / (stripeWeight + gapWeight)');
    expect(source).toContain('abs(fract(cycleCoordinate) - 0.5)');
    expect(source).toContain('clamp(stripeFraction * 0.5, 0.025, 0.475)');

    for (const count of [1, 2, 3]) {
      for (const width of [0.05, 0.5, 0.95]) {
        for (const gap of [0.05, 0.5, 0.95]) {
          const stripeFraction = width / (width + gap);
          const stripeWidth = stripeFraction / count;
          const gapWidth = (1 - stripeFraction) / count;

          expect(stripeWidth).toBeGreaterThan(0);
          expect(gapWidth).toBeGreaterThan(0);
          expect((stripeWidth + gapWidth) * count).toBeCloseTo(1, 12);
        }
      }
    }
  });

  it('sharpens only the bounded stripe edge without changing its period', () => {
    expect(source).toContain("halfStripe * mix(0.9, 0.015, clamp(sharpness / 3.0, 0.0, 1.0))");
    expect(source).toContain('smoothstep(flatEdge, halfStripe, distanceFromCenter)');
    expect(source).toContain('stripeBandProfile(stripeCycle, stripeFraction, u_stripeSharpness)');
    expect(source).toContain('u_linearDensity / TAU');
  });

  it('can decouple stripe scale from ripple scale without changing old presets', () => {
    expect(source).toContain('u_linearScale > 0.000001 ? u_linearScale : u_scale');
    expect(source).toContain('dot(localPos * stripeScale, linearDirection)');
    expect(source).not.toContain('smoothDist * u_shapeReactivity * 150.0 * stripeScale');
  });

  it('can amplify thin-film color without changing the thickness phase', () => {
    expect(source).toContain('vec3 rainbow = clamp(film / filmLuminance, 0.15, 2.5);');
    expect(source).toContain('u_iridescence * u_rainbowBoost');
    expect(source).toContain('0.08 + grazingResponse * 0.92');
  });

  it('exposes shape-only bevel geometry without affecting an empty SDF', () => {
    expect(source).toContain('shapeDistance / max(u_bevelWidth, 1.0)');
    expect(source).toContain('pow(1.0 - bevelT, max(u_bevelProfile, 0.05))');
    expect(source).toContain('shoulderBand * u_shoulder * 1.6');
    expect(source).toContain('float bevelSlope = shaped * u_shapeDepth');
  });
});
