/**
 * Gradient — every classic design gradient from ONE key color.
 *
 * A palette engine + five field constructions. The engine turns the single Key
 * Color into a continuous tonal ramp: t=0 is the shadow end (key sunk toward
 * black, saturation deepened), t=0.5 is the key itself, t=1 is the light end
 * (key lifted toward white, saturation washed out). Hue Drift bends the hue
 * across the ramp (sunset red→orange→cream), and an optional Accent band
 * injects a second, hue-rotated color at a chosen point of the ramp (the pink
 * halo around a blue aura, a navy background behind a warm glow).
 *
 * The Type slider picks how t is laid out over the canvas, rounded to the
 * nearest step (Pencil's paste-safe vocabulary has no enum control):
 *   0 Linear — straight ramp along Angle, through Center.
 *   1 Radial — light core at Center falling off to the shadow end.
 *   2 Hole   — a squashed glowing disc with a hard lower horizon and soft
 *              upward bloom (the "pit of light" / setting-sun poster look).
 *   3 Mesh   — four blobs sampled at different ramp heights, scattered around
 *              Center; a soft multipoint/corner-glow gradient.
 *   4 Sky    — vertical ramp + low-frequency haze wobble + a sun glow at
 *              Center; the dusk-sky look.
 *
 * Static by design (no @time): these are backdrops for posters and UI. Grain
 * is hashed per-pixel, which also dithers away Mach banding.
 */

/** @resolution */
uniform vec2 u_resolution;

// SECTION: Type
/**
 * Which gradient construction to render. (Exports to Pencil as a 0–4 slider:
 * 0 Linear · 1 Radial · 2 Hole · 3 Mesh · 4 Sky.)
 * @label Type
 * @select Linear, Radial, Hole, Mesh, Sky
 * @default 0
 */
uniform float u_type;

// SECTION: Color
/**
 * The one color everything derives from. It sits at the middle of the tonal
 * ramp; shadows, mid-tones, highlights and the accent are all computed from it.
 * @label Key Color
 * @color
 * @default #f4501e
 */
uniform vec3 u_key;

// SECTION: Color
/**
 * How far the shadow end of the ramp sinks toward black. 0 keeps the dark end
 * at the key's own brightness; 1 reaches true black.
 * @label Range Dark
 * @default 0.8
 * @range 0, 1
 */
uniform float u_rangeDark;

// SECTION: Color
/**
 * How far the light end of the ramp lifts toward white — higher also washes
 * its saturation out, so highlights melt into cream/paper instead of neon.
 * @label Range Light
 * @default 0.85
 * @range 0, 1
 */
uniform float u_rangeLight;

// SECTION: Color
/**
 * Hue rotation across the ramp, dark end to light end (±1 = ±180°). Positive
 * drifts the light end clockwise on the wheel — deep red shadows into orange
 * highlights reads instantly as sunset.
 * @label Hue Drift
 * @default 0.25
 * @range -1, 1
 */
uniform float u_hueSpread;

// SECTION: Color
/**
 * Global saturation multiplier over the whole ramp.
 * @label Saturation
 * @default 1
 * @range 0, 2
 */
uniform float u_sat;

// SECTION: Accent
/**
 * Strength of the accent band — a second color, hue-rotated from the key,
 * blended in around one point of the ramp. 0 disables it.
 * @label Amount
 * @default 0
 * @range 0, 1
 */
uniform float u_accentAmt;

// SECTION: Accent
/**
 * Hue rotation of the accent relative to the key (±1 = ±180°, i.e. the
 * complementary color). Blue key + ~+0.4 gives the classic pink halo.
 * @label Hue Shift
 * @default 0.5
 * @range -1, 1
 */
uniform float u_accentHue;

// SECTION: Accent
/**
 * Where on the ramp the accent sits: 0 recolors the shadows (e.g. a navy
 * background behind a warm glow), 1 recolors the highlights.
 * @label Position
 * @default 0.7
 * @range 0, 1
 */
uniform float u_accentPos;

// SECTION: Accent
/**
 * Width of the accent band along the ramp — narrow reads as a ring/stripe,
 * wide as an overall two-tone blend.
 * @label Width
 * @default 0.25
 * @range 0.02, 0.6
 */
uniform float u_accentWidth;

// SECTION: Shape
/**
 * Direction of the ramp for Linear and Sky, in degrees. -90 puts the shadow
 * end at the top and the light end at the bottom.
 * @label Angle
 * @default -90
 * @range -180, 180
 */
uniform float u_angle;

// SECTION: Shape
/**
 * Horizontal anchor: ramp center for Linear, shape center for Radial/Hole,
 * constellation center for Mesh, sun position for Sky.
 * @label Center X
 * @default 0.5
 * @range -0.5, 1.5
 */
uniform float u_cx;

// SECTION: Shape
/**
 * Vertical anchor (0 = bottom, 1 = top). Same role per type as Center X.
 * @label Center Y
 * @default 0.5
 * @range -0.5, 1.5
 */
uniform float u_cy;

// SECTION: Shape
/**
 * Size of the construction: ramp length for Linear/Sky, radius for
 * Radial/Hole. Small = tight and contrasty, large = soft and enveloping.
 * @label Scale
 * @default 1
 * @range 0.1, 2.5
 */
uniform float u_scale;

// SECTION: Shape
/**
 * Where the key color sits along the field — a gamma bend. Low pulls the
 * mid-tone toward the shadow end (long bright falloff), high the opposite.
 * @label Midpoint
 * @default 0.5
 * @range 0.1, 0.9
 */
uniform float u_mid;

// SECTION: Shape
/**
 * S-curve contrast on the field: 0 is a raw linear ramp, 1 compresses the
 * extremes and steepens the middle.
 * @label Contrast
 * @default 0.2
 * @range 0, 1
 */
uniform float u_contrast;

// SECTION: Shape
/**
 * Continuously flips the ramp (1 = fully inverted: light becomes shadow).
 * Turns a glowing core into a dark aura hole, a sunset into dawn.
 * @label Invert
 * @default 0
 * @range 0, 1
 */
uniform float u_invert;

// SECTION: Hole
/**
 * Vertical squash of the Hole disc. 1 is a full circle (setting sun), low
 * values flatten it into the elliptical "pit of light" rim.
 * @label Squash
 * @default 0.45
 * @range 0.1, 1
 */
uniform float u_squash;

// SECTION: Hole
/**
 * Sharpness of the disc's lower horizon edge. High = a crisp cut arc against
 * the background; low melts the bottom like the top.
 * @label Edge
 * @default 0.85
 * @range 0, 1
 */
uniform float u_edge;

// SECTION: Hole
/**
 * The dome of light rising above the hole — strength and reach together. High
 * values push a soft cone of glow several radii up into the background.
 * @label Bloom
 * @default 0.5
 * @range 0, 1
 */
uniform float u_bloom;

// SECTION: Hole
/**
 * Hotspot at the mouth of the hole — a near-white center-bottom highlight, as
 * if the light source sits just inside the pit and shines out.
 * @label Core Light
 * @default 0.5
 * @range 0, 1
 */
uniform float u_core;

// SECTION: Hole
/**
 * Vertical position of the core hotspot inside the disc: -1 is the bottom
 * rim, 0 the center, 1 the top rim.
 * @label Core Pos
 * @default -0.55
 * @range -1, 1
 */
uniform float u_corePos;

// SECTION: Hole
/**
 * Horizontal spread of the core hotspot, as a fraction of the disc radius.
 * @label Core Width
 * @default 0.55
 * @range 0.1, 2
 */
uniform float u_coreW;

// SECTION: Hole
/**
 * Vertical spread of the core hotspot — tall values send the shine up through
 * the middle of the disc.
 * @label Core Height
 * @default 0.9
 * @range 0.1, 2
 */
uniform float u_coreH;

// SECTION: Mesh
/**
 * How far the four blobs scatter from Center toward the corners. 0 stacks
 * them into one soft core, 1 pins a different tone in each corner.
 * @label Scatter
 * @default 0.5
 * @range 0, 1
 */
uniform float u_scatter;

// SECTION: Mesh
/**
 * Radius of each blob's soft influence. Small = distinct color pools with
 * background between them, large = one continuous melted wash.
 * @label Blob Size
 * @default 0.55
 * @range 0.15, 1.2
 */
uniform float u_blobSize;

// SECTION: Mesh
/**
 * Rotates the four-blob constellation around Center, in degrees — moves which
 * corner holds the light and which the shadow.
 * @label Rotate
 * @default 0
 * @range -180, 180
 */
uniform float u_rot;

// SECTION: Sky
/**
 * Low-frequency noise wobble on the Sky ramp — the soft horizontal unevenness
 * of real dusk light through atmosphere.
 * @label Haze
 * @default 0.35
 * @range 0, 1
 */
uniform float u_haze;

// SECTION: Sky
/**
 * Strength of the sun glow at Center — lifts the ramp locally toward the
 * light end (and through any accent band on the way).
 * @label Sun Glow
 * @default 0.35
 * @range 0, 1
 */
uniform float u_sun;

// SECTION: Sky
/**
 * Radius of the sun glow.
 * @label Sun Size
 * @default 0.35
 * @range 0.05, 1
 */
uniform float u_sunSize;

// SECTION: Finish
/**
 * Per-pixel film grain. Even a little breaks gradient banding and gives the
 * printed-poster texture; a hairline of dither is always on.
 * @label Grain
 * @default 0.15
 * @range 0, 1
 */
uniform float u_grain;

// SECTION: Finish
/**
 * Darkens the corners to pull focus inward.
 * @label Vignette
 * @default 0
 * @range 0, 1
 */
uniform float u_vignette;

vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

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

vec2 rot2(vec2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

/** Midpoint gamma + S-curve contrast, applied to the FIELD (not the palette). */
float shapeT(float t) {
  t = clamp(t, 0.0, 1.0);
  t = pow(t, log(0.5) / log(clamp(u_mid, 0.06, 0.94)));
  return mix(t, t * t * (3.0 - 2.0 * t), u_contrast);
}

/** Continuous ramp invert. */
float inv(float t) {
  return mix(t, 1.0 - t, u_invert);
}

/**
 * Monotone C1 cubic through (0,0) → (0.5, a) → (1,1) with slope 1 at the
 * joint. Replaces an anchored gamma here: pow(t, g) has unbounded slope at
 * t=0 whenever the anchor nears 1 (any bright key), which rendered the
 * faintest glow tails at near-full brightness and drew a hard iso-line
 * contour where they underflowed to zero. The cubic's slope is bounded
 * (≤ 2·a), so tails fade smoothly; the anchor clamp keeps it monotone.
 */
float anchoredCurve(float t, float a) {
  a = clamp(a, 0.17, 0.83);
  float s;
  float p0;
  float p1;
  float m0;
  float m1;
  if (t < 0.5) {
    s = t * 2.0;
    p0 = 0.0;
    p1 = a;
    m0 = a;
    m1 = 0.5;
  } else {
    s = (t - 0.5) * 2.0;
    p0 = a;
    p1 = 1.0;
    m0 = 0.5;
    m1 = 1.0 - a;
  }
  float s2 = s * s;
  float s3 = s2 * s;
  return (2.0 * s3 - 3.0 * s2 + 1.0) * p0 + (s3 - 2.0 * s2 + s) * m0 +
         (-2.0 * s3 + 3.0 * s2) * p1 + (s3 - s2) * m1;
}

/**
 * The palette engine: tonal position t (0 shadow … 1 light) → color, all
 * derived from the key. Value follows a smooth curve anchored so t=0.5 lands
 * near the key's own brightness whatever the dark/light range is; saturation
 * deepens into shadow and washes toward the light; hue drifts linearly and the
 * accent band overrides it locally.
 */
vec3 ramp(float t) {
  t = clamp(t, 0.0, 1.0);
  vec3 key = rgb2hsv(u_key);

  float vDark = key.z * (1.0 - u_rangeDark);
  float vLight = mix(key.z, 1.0, u_rangeLight);
  float span = max(vLight - vDark, 1.0e-4);
  float v = vDark + span * anchoredCurve(t, (key.z - vDark) / span);

  float sDark = clamp(key.y * (1.0 + 0.4 * u_rangeDark), 0.0, 1.0);
  float sLight = key.y * (1.0 - 0.75 * u_rangeLight);
  float s = mix(sDark, sLight, t) * u_sat;

  float h = key.x + u_hueSpread * 0.5 * (t - 0.5);

  float ad = (t - u_accentPos) / max(u_accentWidth, 0.02);
  float w = u_accentAmt * exp(-ad * ad);
  h = mix(h, key.x + u_accentHue * 0.5, w);
  s += 0.3 * w;

  return hsv2rgb(vec3(fract(h), clamp(s, 0.0, 1.0), clamp(v, 0.0, 1.0)));
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float asp = u_resolution.x / u_resolution.y;
  vec2 pa = vec2((uv.x - u_cx) * asp, uv.y - u_cy);
  float mode = floor(u_type + 0.5);
  float scale = max(u_scale, 0.02);

  vec3 col;
  if (mode < 2.5) {
    float t;
    if (mode < 0.5) {
      // Linear: signed distance along the angle direction, through Center.
      float a = radians(u_angle);
      t = dot(vec2(uv.x - u_cx, uv.y - u_cy), vec2(cos(a), sin(a))) / scale + 0.5;
    } else if (mode < 1.5) {
      // Radial: light core at Center, shadow end outward.
      t = 1.0 - length(pa) / scale;
    } else {
      // Hole: three additive terms. A crisp-rimmed disc (hard lower horizon,
      // moderately soft top), a dome of light rising above it whose vertical
      // reach scales with Bloom, and a core hotspot at the disc's mouth. The
      // dome hugs the rim below the horizon so the hard edge stays crisp.
      float sq = max(u_squash, 0.1);
      vec2 qn = vec2(pa.x, pa.y / sq) / scale;
      float rr = length(qn);
      float above = smoothstep(-0.05, 0.3, pa.y / scale);
      float feather = mix(0.012 + 0.3 * (1.0 - u_edge), 0.18, above);
      float disc = 1.0 - smoothstep(1.0 - feather * 0.25, 1.0 + feather, rr);

      float reach = mix(0.45, 0.6 + 2.6 * u_bloom, smoothstep(-0.1, 0.1, pa.y / scale));
      vec2 gq = vec2(pa.x / (1.0 + 0.9 * u_bloom), pa.y / reach) / scale;
      float glow = u_bloom * exp(-dot(gq, gq) * 1.8);

      vec2 cd = (qn - vec2(0.0, u_corePos)) / vec2(max(u_coreW, 0.05), max(u_coreH, 0.05));
      float core = u_core * exp(-dot(cd, cd)) * disc;

      // The dome is attenuated inside the disc so the interior stays a mid
      // tone and the Core hotspot can read against it.
      t = disc * 0.66 + glow * (1.0 - 0.75 * disc) + core;
    }
    col = ramp(inv(shapeT(t)));
  } else if (mode < 3.5) {
    // Mesh: four blobs at fixed ramp heights, gaussian-blended over a
    // mid-tone background. Positions live in aspect-true space so blobs stay
    // round on any canvas.
    vec2 p = vec2(uv.x * asp, uv.y);
    vec2 c = vec2(u_cx * asp, u_cy);
    float a = radians(u_rot);
    float push = u_scatter * 1.6;
    vec2 d0 = p - (c + rot2(vec2(-0.38, 0.36), a) * push);
    vec2 d1 = p - (c + rot2(vec2(0.42, 0.30), a) * push);
    vec2 d2 = p - (c + rot2(vec2(0.36, -0.34), a) * push);
    vec2 d3 = p - (c + rot2(vec2(-0.34, -0.40), a) * push);
    float s2 = u_blobSize * u_blobSize;
    float w0 = exp(-dot(d0, d0) / s2);
    float w1 = exp(-dot(d1, d1) / s2);
    float w2 = exp(-dot(d2, d2) / s2);
    float w3 = exp(-dot(d3, d3) / s2);
    float wb = 0.06;
    col = (w0 * ramp(inv(1.0)) + w1 * ramp(inv(0.68)) + w2 * ramp(inv(0.35)) +
           w3 * ramp(inv(0.03)) + wb * ramp(0.5)) /
          (w0 + w1 + w2 + w3 + wb);
  } else {
    // Sky: angled ramp + two octaves of haze wobble + a sun glow at Center.
    float a = radians(u_angle);
    float t = dot(uv - vec2(0.5, 0.5), vec2(cos(a), sin(a))) / scale + 0.5;
    float ss = max(u_sunSize, 0.05);
    t += exp(-dot(pa, pa) / (ss * ss)) * u_sun;
    float n = vnoise(uv * vec2(1.5, 3.5)) * 0.65 +
              vnoise(uv * vec2(3.0, 7.0) + vec2(11.7, 5.3)) * 0.35;
    // Window the wobble so it dies at the ramp extremes — otherwise the clamp
    // plateau draws a hard contour where t leaves [0, 1].
    float win = clamp(4.0 * t * (1.0 - t), 0.0, 1.0);
    t += (n - 0.5) * u_haze * 0.6 * win;
    col = ramp(inv(shapeT(t)));
  }

  // Finish: vignette, then grain (a hairline of dither stays on at Grain 0).
  float r = length(vec2((uv.x - 0.5) * asp, uv.y - 0.5)) * 2.0;
  col *= 1.0 - u_vignette * 0.7 * smoothstep(0.5, 1.6, r);
  col += (hash12(gl_FragCoord.xy) - 0.5) * (u_grain * 0.22 + 0.006);

  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
