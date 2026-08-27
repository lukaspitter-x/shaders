/**
 * Chrome Flow — a full-canvas sheet of polished liquid chrome.
 *
 * A domain-warped noise height field stands in for a rippling metal surface;
 * its finite-difference normal reflects a straight-on view into a procedural
 * studio environment: a bright sky above a dark floor, soft white panels, and
 * thin strip lights that read as the crisp bright contour lines chrome shows
 * along every fold. Mid-tones pull toward a warm tint the way real chrome
 * picks up a room. Covers the full quad; no host shape required.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Surface
/**
 * Number of ripple folds across the canvas width.
 * @label Scale
 * @default 1.6
 * @range 0.5, 8
 */
uniform float u_scale;

/**
 * Steepness of the folds. Higher tilts the surface further and reflects more
 * of the environment's extremes (blacks and whites).
 * @label Height
 * @default 1.1
 * @range 0, 3
 */
uniform float u_height;

/**
 * How much the noise bends its own coordinates — the liquid, drapey swirl.
 * @label Warp
 * @default 0.8
 * @range 0, 4
 */
uniform float u_warp;

/**
 * Sharpens rounded bumps into creased ridges and pinched valleys.
 * @label Fold
 * @default 0.55
 * @range 0, 1
 */
uniform float u_fold;

/**
 * Speed of the slow liquid drift. 0 freezes the surface.
 * @label Flow
 * @default 0.08
 * @range 0, 1
 */
uniform float u_flow;

// SECTION: Environment
/**
 * Overall brightness of the reflected room.
 * @label Brightness
 * @default 1
 * @range 0.2, 2
 */
uniform float u_brightness;

/**
 * Contrast of the reflection around mid gray. Chrome wants a lot.
 * @label Contrast
 * @default 1.15
 * @range 0.5, 3
 */
uniform float u_contrast;

/**
 * Vertical position of the horizon — the split between the bright ceiling
 * and the dark floor — in the reflected environment.
 * @label Horizon
 * @default 0.5
 * @range 0, 1
 */
uniform float u_horizon;

/**
 * Intensity of the thin strip lights that draw bright contour lines along
 * the folds.
 * @label Strip Lights
 * @default 0.8
 * @range 0, 1
 */
uniform float u_strips;

/**
 * Number of strip lights stacked across the environment.
 * @label Strip Count
 * @default 6
 * @range 1, 16
 */
uniform float u_stripCount;

/**
 * Edge crispness of the strip lights: 0 = soft glow, 1 = razor line.
 * @label Strip Sharpness
 * @default 0.75
 * @range 0, 1
 */
uniform float u_stripSharp;

// SECTION: Material
/**
 * Tint multiplied over the whole reflection.
 * @label Tint
 * @color
 * @default #ffffff
 */
uniform vec3 u_tint;

/**
 * Warm tone the mid-tones pull toward — the beige/bronze cast chrome picks
 * up from a lit room.
 * @label Warm Tone
 * @color
 * @default #c9a98a
 */
uniform vec3 u_warm;

/**
 * How strongly mid-tones take on the warm tone.
 * @label Warmth
 * @default 0.35
 * @range 0, 1
 */
uniform float u_warmth;

/**
 * Micro-roughness: softens strip lights and panel edges toward satin.
 * @label Roughness
 * @default 0.12
 * @range 0, 1
 */
uniform float u_rough;

const int OCTAVES = 4;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amp = 0.5;
  float norm = 0.0;
  mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  for (int i = 0; i < OCTAVES; i++) {
    sum += amp * vnoise(p);
    norm += amp;
    p = rot * p * 2.03 + vec2(1.7, 9.2);
    amp *= 0.42;
  }
  return sum / norm;
}

// Height field: domain-warped fbm, optionally folded into ridges.
float height(vec2 p, float t) {
  vec2 q = vec2(fbm(p + vec2(0.0, t)), fbm(p + vec2(5.2, 1.3) - vec2(t, 0.0)));
  vec2 r = p + u_warp * (q - 0.5) * 1.5;
  float h = fbm(r + vec2(t * 0.5, -t * 0.3));
  float ridge = 1.0 - abs(h * 2.0 - 1.0);
  ridge = ridge * ridge;
  return mix(h, ridge, u_fold);
}

// Strip lights: repeating thin bright bands along the environment's vertical.
float strips(float y, float soft) {
  float w = fract(y * u_stripCount);
  float d = abs(w - 0.5) * 2.0;
  float edge = mix(0.85, 0.12, u_stripSharp) + soft * 0.6;
  return 1.0 - smoothstep(0.1, 0.1 + edge, d);
}

vec3 environment(vec3 r) {
  float soft = u_rough * 0.6;
  // Compress the hemisphere so a moderate tilt sweeps from floor to ceiling.
  float y = clamp(0.5 + r.y * 1.3 + (u_horizon - 0.5), 0.0, 1.0);
  float x = clamp(0.5 + r.x * 1.3, 0.0, 1.0);

  // Wide ceiling / floor gradient: a flat surface reflects mid silver.
  float sky = smoothstep(0.1 - soft, 0.9 + soft, y);
  float base = mix(0.08, 0.72, sky);

  // Bright softbox sheet just above the horizon, dark flag just below it.
  float sheet = exp(-pow((y - 0.66) / (0.1 + soft), 2.0)) * 0.38;
  float flag = exp(-pow((y - 0.4) / (0.05 + soft), 2.0)) * 0.26;

  // Side panels: one bright, one dim, so left/right folds differ.
  float panelL = smoothstep(0.4 + soft, 0.15 - soft, x) * 0.22;
  float panelR = smoothstep(0.6 - soft, 0.9 + soft, x) * -0.12;

  // Thin strip lights: the crisp contour lines chrome shows along folds.
  float lines = strips(y * 1.0 + x * 0.12, soft) * u_strips * 0.28;

  float lum = base + sheet - flag + panelL + panelR + lines;
  return vec3(lum);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;
  vec2 p = vec2(uv.x * aspect, uv.y) * u_scale;
  float t = u_time * u_flow;

  // Finite-difference normal of the height field.
  float e = 0.75 / u_resolution.y * u_scale;
  float hC = height(p, t);
  float hX = height(p + vec2(e, 0.0), t);
  float hY = height(p + vec2(0.0, e), t);
  float amp = u_height * 0.32;
  vec3 n = normalize(vec3(-(hX - hC) / e * amp, -(hY - hC) / e * amp, 1.0));

  // Straight-on viewer looking down -z; reflect into the environment.
  vec3 view = vec3(0.0, 0.0, 1.0);
  vec3 r = reflect(-view, n);

  vec3 env = environment(r);

  // Contrast around mid gray, then warm the mid-tones.
  float lum = env.r;
  lum = (lum - 0.5) * u_contrast + 0.5;
  lum = clamp(lum, 0.0, 1.0);
  float mid = 1.0 - abs(lum * 2.0 - 1.0);
  vec3 col = mix(vec3(lum), u_warm * lum * 1.15, u_warmth * mid);

  // Fresnel: grazing folds brighten slightly toward the ceiling white.
  float fres = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
  col += fres * 0.15;

  col *= u_brightness * u_tint;
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
