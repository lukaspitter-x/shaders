/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * Overall motion speed.
 * @label Speed
 * @default 0.4
 * @range 0, 2
 */
uniform float u_speed;

/**
 * Zoom into the field.
 * @label Scale
 * @default 3.0
 * @range 0.5, 8
 */
uniform float u_scale;

/**
 * Domain-warp strength — how much the field folds into itself.
 * @label Warp
 * @default 0.8
 * @range 0, 2
 */
uniform float u_warp;

/**
 * Contrast of the bands.
 * @label Contrast
 * @default 1.2
 * @range 0.2, 3
 */
uniform float u_contrast;

/** @label Color A @color @default #06121f */
uniform vec3 u_colorA;
/** @label Color B @color @default #1d4e6b */
uniform vec3 u_colorB;
/** @label Color C @color @default #46c6c0 */
uniform vec3 u_colorC;
/** @label Color D @color @default #f0c987 */
uniform vec3 u_colorD;

vec3 palette(float t) {
  t = clamp(t, 0.0, 1.0);
  float s = t * 3.0;
  if (s < 1.0) return mix(u_colorA, u_colorB, s);
  if (s < 2.0) return mix(u_colorB, u_colorC, s - 1.0);
  return mix(u_colorC, u_colorD, s - 2.0);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 6; i++) {
    v += a * vnoise(p);
    p = p * 2.0 + 7.3;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 uv = (gl_FragCoord.xy - 0.5 * u_resolution) / min(u_resolution.x, u_resolution.y);
  float t = u_time * u_speed;
  vec2 p = uv * u_scale;

  // two-level domain warp
  vec2 q = vec2(fbm(p + t * 0.2), fbm(p + vec2(5.2, 1.3) - t * 0.15));
  vec2 r = vec2(
    fbm(p + u_warp * q + vec2(1.7, 9.2) + t * 0.1),
    fbm(p + u_warp * q + vec2(8.3, 2.8) - t * 0.12));
  float f = fbm(p + u_warp * r);

  float band = pow(0.5 + 0.5 * sin(6.2831 * (f * u_contrast + t * 0.1)), 1.5);
  vec3 col = palette(f * 0.7 + 0.15 * band);
  col += band * 0.12;
  col = pow(col, vec3(0.9));
  gl_FragColor = vec4(col, 1.0);
}
