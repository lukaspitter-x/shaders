/**
 * Chrome Drape — a sheet of polished, champagne-tinted chrome hanging in
 * tall, flowing folds.
 *
 * The surface is a procedural height field: a set of near-vertical folds
 * (rounded ridges, sharp creases) whose spacing and path are bent by a slow
 * domain-warp, riding on a broad low-frequency swell. Its finite-difference
 * gradient gives a normal; the normal reflects a straight-on view into a
 * procedural studio environment — a warm vertical sky ramp plus a soft
 * key-light band — so every ridge catches a bright edge and every crease
 * falls into a dark seam, exactly as a mirror-finish fabric would. A
 * Fresnel term brightens grazing slopes and a tone curve keeps the metal
 * satin rather than plastic.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Folds
/**
 * How many folds span the canvas width.
 * @label Count
 * @default 3.5
 * @range 1, 8
 */
uniform float u_count;

/**
 * Rotation of the fold direction, in degrees. 0 hangs the folds vertically.
 * @label Angle
 * @default 6
 * @range -90, 90
 */
uniform float u_angle;

/**
 * How strongly the folds meander — bends the straight pleats into S-curves
 * and lets them merge and split.
 * @label Meander
 * @default 1.4
 * @range 0, 2
 */
uniform float u_warp;

/**
 * Vertical stretch of the meander. Higher keeps each fold's path smooth over
 * the full height; lower makes it wriggle.
 * @label Stretch
 * @default 2.6
 * @range 0.5, 5
 */
uniform float u_stretch;

/**
 * Depth of the folds — how far the ridges stand out from the sheet. Drives
 * how steep the slopes get and therefore how much environment they reflect.
 * @label Depth
 * @default 0.6
 * @range 0, 1.5
 */
uniform float u_depth;

/**
 * Crease sharpness: 0 is a soft sine ripple, 1 pinches the valleys into
 * knife-edge seams with wide rounded crowns between them.
 * @label Crease
 * @default 0.55
 * @range 0, 1
 */
uniform float u_crease;

/**
 * Variation in fold height — some pleats stand proud, others sink almost
 * flat into the sheet.
 * @label Variation
 * @default 0.85
 * @range 0, 1
 */
uniform float u_variation;

/**
 * A broad, slow undulation of the whole sheet underneath the folds — the
 * gentle billow that keeps the flat areas from reading as a plane.
 * @label Swell
 * @default 0.5
 * @range 0, 1
 */
uniform float u_swell;

// SECTION: Motion
/**
 * Speed of the drift through the meander field — the folds slowly re-form.
 * 0 freezes the sheet.
 * @label Speed
 * @default 0.12
 * @range 0, 1
 */
uniform float u_speed;

/**
 * How much the folds slide along their own length over time (the cloth
 * pouring downward).
 * @label Flow
 * @default 0.3
 * @range 0, 1
 */
uniform float u_flow;

// SECTION: Material
/**
 * Body color of the metal — the mid-tone every reflection is tinted by.
 * @label Tint
 * @color
 * @default #cfc3b5
 */
uniform vec3 u_tint;

/**
 * Color of the dark reflections (the deep seams and the shadowed flanks).
 * @label Shadow
 * @color
 * @default #4a4542
 */
uniform vec3 u_shadow;

/**
 * Color of the bright reflections along the ridge crowns.
 * @label Highlight
 * @color
 * @default #fff8ee
 */
uniform vec3 u_highlight;

/**
 * Micro-roughness of the finish: 0 is a hard mirror with knife-thin
 * highlights; 1 is brushed satin with wide, soft ones.
 * @label Roughness
 * @default 0.25
 * @range 0, 1
 */
uniform float u_roughness;

/**
 * Overall contrast of the reflection — how far the darks sink and the
 * lights lift from the tint.
 * @label Contrast
 * @default 0.8
 * @range 0, 1.5
 */
uniform float u_contrast;

// SECTION: Light
/**
 * Direction of the key light, in degrees (0 = from the right, 90 = above).
 * @label Light Angle
 * @default 150
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * Strength of the key-light highlight band on the ridges.
 * @label Key Light
 * @default 0.7
 * @range 0, 2
 */
uniform float u_keyLight;

/**
 * Strength of the fill from the opposite side — a dimmer second rim so the
 * shadowed flank of each fold still shows an edge.
 * @label Fill Light
 * @default 0.3
 * @range 0, 1
 */
uniform float u_fillLight;

/**
 * Brightening of grazing surfaces (Fresnel) — lifts the steep flanks toward
 * the highlight color.
 * @label Fresnel
 * @default 0.4
 * @range 0, 1
 */
uniform float u_fresnel;

// SECTION: Finish
/**
 * Per-pixel grain. Breaks banding on the long, smooth gradients.
 * @label Grain
 * @default 0.08
 * @range 0, 1
 */
uniform float u_grain;

const int OCTAVES = 4;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 w = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  float sum = 0.0;
  for (int i = 0; i < OCTAVES; i++) {
    v += a * vnoise(p);
    sum += a;
    p = p * 2.03 + vec2(17.1, 9.7);
    a *= 0.5;
  }
  return v / sum;
}

vec2 rot2(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/**
 * The sheet at p (aspect-true, fold-aligned space; x runs across the folds,
 * y along them). Returns (height, position within the fold 0..1, ridge
 * height 0..1) — the last two drive crease lines and valley occlusion.
 */
vec3 sheet(vec2 p) {
  float t = u_time * u_speed;
  vec2 q = vec2(p.x, p.y / max(u_stretch, 0.1));

  // Meander: a slow warp of the across-fold coordinate. Two decorrelated
  // fbm lookups so neighbouring folds don't bend in lockstep.
  float w1 = fbm(q * 0.9 + vec2(t * 0.7, -u_time * u_flow * 0.25));
  float w2 = fbm(q * 0.45 + vec2(-t * 0.4 + 5.3, u_time * u_flow * 0.12 + 2.1));
  float x = p.x * u_count + (w1 - 0.5) * 2.2 * u_warp + (w2 - 0.5) * 1.6 * u_warp;

  // Fold profile: sin over one period has a corner at the period boundary —
  // that's the crease. Raising it to a power widens the crown and pinches
  // the valley further.
  float f = fract(x);
  float ridge = pow(sin(3.14159265 * f), 1.0 + 3.0 * u_crease);

  // Per-fold amplitude so pleats differ in prominence.
  float amp = fbm(vec2(floor(x) * 0.37, q.y * 0.5 + t * 0.2) + 11.0);
  ridge *= mix(1.0, 0.25 + 1.1 * amp, u_variation);

  // Broad swell under everything.
  float swell = fbm(q * 0.35 + vec2(-t * 0.3 + 7.7, t * 0.15)) - 0.5;

  return vec3(ridge * u_depth + swell * u_swell * 1.4, f, ridge);
}

float height(vec2 p) {
  return sheet(p).x;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float asp = u_resolution.x / u_resolution.y;
  vec2 p = rot2(vec2((uv.x - 0.5) * asp, uv.y - 0.5), radians(u_angle));

  vec3 sh = sheet(p);

  // Normal from the height field via central differences in fold space.
  float e = 0.003;
  float hx = (height(p + vec2(e, 0.0)) - height(p - vec2(e, 0.0))) / (2.0 * e);
  float hy = (height(p + vec2(0.0, e)) - height(p - vec2(0.0, e))) / (2.0 * e);
  vec3 n = normalize(vec3(-hx * 0.13, -hy * 0.13, 1.0));
  // Undo the fold rotation so lighting is in canvas space.
  n.xy = rot2(n.xy, -radians(u_angle));

  // Straight-on view: reflection vector.
  vec3 r = vec3(2.0 * n.z * n.x, 2.0 * n.z * n.y, 2.0 * n.z * n.z - 1.0);

  // ---- Environment ----
  // A soft studio: slightly brighter above the horizon, a key softbox in
  // the light direction, a dimmer fill opposite, and a dark band on the
  // side away from the key so the shadowed flanks sink.
  float la = radians(u_lightAngle);
  vec2 ldir = vec2(cos(la), sin(la));
  float along = dot(r.xy, ldir);
  float soft = mix(0.04, 0.5, u_roughness);

  float base = 0.42 + 0.10 * r.y;
  float key = exp(-pow(1.0 - along, 2.0) / soft) * u_keyLight;
  float glow = exp(-pow(1.0 - along, 2.0) / (soft * 6.0 + 0.5)) * u_keyLight * 0.12;
  float fill = exp(-pow(1.0 + along, 2.0) / (soft * 1.5 + 0.1)) * u_fillLight;
  float dark = exp(-pow(0.5 + along, 2.0) / 0.22) * 0.3;
  float fres = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0) * u_fresnel;

  // Valley occlusion: the bottom of each fold sees less of the environment,
  // and the crease itself is a thin dark seam.
  float ao = mix(0.6, 1.0, smoothstep(0.0, 0.5, sh.z));
  float dc = min(sh.y, 1.0 - sh.y);
  float seam = 1.0 - smoothstep(0.0, 0.03 + 0.04 * (1.0 - u_crease), dc);
  ao *= 1.0 - 0.55 * seam * u_crease;
  // The sharp fold just beside the seam catches a hairline specular.
  float rim = exp(-pow((dc - 0.04) / 0.018, 2.0)) * u_crease * 0.3;

  // ---- Tone ----
  float lum = (base + key * 0.75 + glow + fill * 0.45 - dark + fres * 0.5) * ao + rim;
  lum = 0.45 + (lum - 0.45) * (0.5 + u_contrast);
  lum = clamp(lum, 0.0, 1.5);

  vec3 col;
  if (lum < 0.45) {
    col = mix(u_shadow, u_tint, smoothstep(0.0, 0.45, lum));
  } else {
    col = mix(u_tint, u_highlight, pow(clamp((lum - 0.45) / 0.55, 0.0, 1.0), 1.6));
  }
  // Specular beyond 1.0 pushes toward pure white.
  col = mix(col, vec3(1.0), clamp(lum - 1.0, 0.0, 0.5));

  col += (hash12(gl_FragCoord.xy) - 0.5) * (u_grain * 0.12 + 0.004);

  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
