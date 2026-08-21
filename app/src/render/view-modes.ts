/**
 * Workbench-only viewport modes: debug shaders swapped into the viewport in
 * place of the experiment. These are NOT Pencil experiments — they never
 * export — but they compile through the same prelude, so they stay in the
 * annotated dialect.
 *
 * - SDF view: visualizes the host shape's distance field (iso bands, sign
 *   coloring, zero-crossing line).
 * - Env view: equirect panorama of the procedural studio environment that
 *   `chrome.glsl` reflects (horizon + softbox stripes + optional image env).
 *   Uniform names match chrome's so the live dial values flow straight in;
 *   `envPreviewAvailable` gates the mode on that contract (guarded by a test).
 */
import { parseShader, type ParsedShader } from '@/glsl/parse-annotations';

export type ViewMode = 'fill' | 'sdf' | 'env';

export const SDF_VIEW_SOURCE = `/** @resolution */
uniform vec2 u_resolution;

/** @sdf */
uniform sampler2D u_shape;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float d = texture2D(u_shape, uv).r;
  float inside = step(0.0, d);

  // Iso bands every 24 canvas px show the field's shape and smoothness.
  float band = abs(fract(d / 24.0) - 0.5) * 2.0;
  float shade = 0.3 + 0.55 * band;
  vec3 inCol = vec3(0.22, 0.5, 0.95) * shade + 0.12;
  vec3 outCol = vec3(0.9, 0.34, 0.22) * shade * 0.55;
  vec3 col = mix(outCol, inCol, inside);

  // White line at the zero crossing (the silhouette).
  float edge = 1.0 - smoothstep(0.0, 2.0, abs(d));
  col = mix(col, vec3(1.0), edge);

  gl_FragColor = vec4(col, 1.0);
}
`;

export const ENV_VIEW_SOURCE = `/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @label Roughness */
uniform float u_rough;

/** @label Contrast */
uniform float u_contrast;

/** @label Horizon */
uniform float u_horizon;

/** @label Stripes */
uniform float u_stripeFreq;

/** @label Stripe Strength */
uniform float u_stripeAmt;

/** @label Env Rotation */
uniform float u_envRotation;

/** @label View Tilt */
uniform float u_tilt;

/** @label Auto Sweep */
uniform float u_sweep;

/** @label Env Image */
uniform sampler2D u_env;

/** @label Env Image Mix */
uniform float u_envMix;

/** @label Env Zoom */
uniform float u_envZoom;

// Equirect panorama: x → azimuth (full turn), y → the elevation coordinate
// chrome.glsl indexes with (r.y). The env math below MUST mirror chrome.glsl.
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float rot = radians(u_envRotation) + u_time * radians(u_sweep);
  float az0 = (uv.x - 0.5) * 6.2831853;
  float e = clamp((uv.y - 0.5) * 2.0, -1.0, 1.0);
  float azim = az0 + rot;
  float elev = e + u_tilt;

  float rough = clamp(u_rough, 0.0, 1.0);
  float soft = mix(0.5, 0.035, u_horizon);
  soft = max(soft, rough * 0.45);
  float horizon = smoothstep(-soft, soft, elev);
  float sky = mix(0.85, 0.5, clamp(elev, 0.0, 1.0));
  float ground = mix(0.04, 0.28, clamp(-elev, 0.0, 1.0));
  float envL = mix(ground, sky, horizon);

  float bars = 0.5 + 0.5 * cos(azim * u_stripeFreq);
  bars = pow(bars, mix(6.0, 1.2, rough));
  envL += u_stripeAmt * (bars - 0.35) * horizon * 0.9;

  envL = mix(envL, 0.42, rough * 0.6);
  envL = clamp(0.45 + (envL - 0.45) * u_contrast, 0.0, 1.6);

  vec3 envC = vec3(envL);
  if (u_envMix > 0.001) {
    // Reconstruct the reflection vector this panorama direction corresponds
    // to, then sphere-map exactly like chrome.glsl.
    float k = sqrt(max(1.0 - e * e, 0.0));
    vec2 rr = vec2(sin(az0) * k, e);
    float rz = cos(az0) * k;
    vec2 rxy = rr / max(u_envZoom, 0.05);
    float m = 2.0 * sqrt(rxy.x * rxy.x + rxy.y * rxy.y + (rz + 1.0) * (rz + 1.0));
    vec2 suv = rxy / max(m, 1e-4) + 0.5;
    suv.x = fract(suv.x + rot * 0.15915494);
    suv.y = 1.0 - suv.y;
    vec3 img = texture2D(u_env, suv).rgb;
    envC = mix(envC, img * (0.4 + 0.8 * envL), u_envMix);
  }

  vec3 hi = max(envC - 0.75, 0.0);
  vec3 col = clamp(min(envC, vec3(0.75)) + hi / (1.0 + 2.0 * hi), 0.0, 1.0);
  gl_FragColor = vec4(col, 1.0);
}
`;

/** User-uniform names the env view reads — must exist on the experiment. */
export const ENV_VIEW_UNIFORMS = [
  'u_rough',
  'u_contrast',
  'u_horizon',
  'u_stripeFreq',
  'u_stripeAmt',
  'u_envRotation',
  'u_tilt',
  'u_sweep',
  'u_env',
  'u_envMix',
  'u_envZoom',
] as const;

/** The env view only makes sense for shaders sharing chrome's env dials. */
export function envPreviewAvailable(parsed: ParsedShader | null): boolean {
  if (!parsed) return false;
  const names = new Set(parsed.uniforms.map((u) => u.name));
  return ENV_VIEW_UNIFORMS.every((n) => names.has(n));
}

export const SDF_VIEW_PARSED = parseShader(SDF_VIEW_SOURCE);
export const ENV_VIEW_PARSED = parseShader(ENV_VIEW_SOURCE);
