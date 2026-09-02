/**
 * Glass Marbles — one big glass sphere with small coloured glass balls
 * whirling inside it.
 *
 * Construction (all analytic, Pencil-safe, no raymarching): each pixel casts
 * a slightly perspective ray at the big sphere. The ray refracts in through
 * the front face, is traced against the inner balls (nearest hit, then the
 * ball behind it through the first ball's lens), and finally refracts out
 * the back face to sample the soft background that fills the sphere. The
 * interior is traced three times with slightly different refractive indices
 * for R, G and B, which is what gives the chromatic aberration fringes.
 *
 * Colour harmony: ball colours are not picked directly. One key colour, a
 * harmony scheme and a seed generate an OKLCH palette (analogous, triadic,
 * tetradic, ...) around the key's hue, chroma and lightness, so every
 * combination stays in tune. The sphere's inner background is a pale tint
 * from the same harmony. Spin the seeds to randomise colours or layout
 * without leaving the scheme.
 *
 * Environment: a procedural studio (sky, floor, key light, softbox windows)
 * is reflected by every glass surface and, faintly, seen through the sphere
 * so the refraction has something to bend. An equirectangular environment
 * image can replace it for reflections and/or the view through the glass.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Sphere
/**
 * Radius of the big sphere relative to the short side of the canvas.
 * 1 touches the edges.
 * @label Size
 * @default 0.82
 * @range 0.3, 1.2
 */
uniform float u_size;

/**
 * Colour of the canvas around the sphere.
 * @label Outside
 * @color
 * @default #000000
 */
uniform vec3 u_outside;

/**
 * Opacity of the canvas around the sphere. 0 leaves it transparent.
 * @label Outside Opacity
 * @default 0
 * @range 0, 1
 */
uniform float u_outsideOpacity;

// SECTION: Text Backdrop
/**
 * A radial gradient laid over the middle of the sphere, above everything,
 * to keep text placed there readable. Use a light or dark colour.
 * @label Backdrop Colour
 * @color
 * @default #ffffff
 */
uniform vec3 u_backdropColor;

/**
 * Opacity of the backdrop at its centre. 0 hides it.
 * @label Backdrop Opacity
 * @default 0
 * @range 0, 1
 */
uniform float u_backdropOpacity;

/**
 * Radius of the backdrop relative to the sphere.
 * @label Backdrop Size
 * @default 0.6
 * @range 0.1, 1.2
 */
uniform float u_backdropSize;

/**
 * How gradually the backdrop fades out toward its edge. 0 is a hard disc,
 * 1 fades from the centre.
 * @label Backdrop Softness
 * @default 0.6
 * @range 0, 1
 */
uniform float u_backdropSoftness;

// SECTION: Glass
/**
 * How strongly the sphere bends what is inside it. 0 is flat window glass,
 * 1 is a dense crystal ball.
 * @label Distortion
 * @default 0.45
 * @range 0, 3
 */
uniform float u_refraction;

/**
 * Colour fringing: red, green and blue bend by different amounts.
 * @label Aberration
 * @default 0.35
 * @range 0, 1
 */
uniform float u_aberration;

/**
 * Molten wobble of the glass surface, warping the view through it.
 * @label Ripple
 * @default 0
 * @range 0, 1
 */
uniform float u_ripple;

/**
 * Spatial frequency of the ripple.
 * @label Ripple Scale
 * @default 1
 * @range 0.3, 3
 */
uniform float u_rippleScale;

/**
 * Strength of the studio reflection on the glass surfaces.
 * @label Reflection
 * @default 0.6
 * @range 0, 1
 */
uniform float u_reflection;

/**
 * Keeps the sphere's reflections, highlight and studio structure to the
 * rim: 0 shows them everywhere, 1 clears the centre completely.
 * @label Reflection Falloff
 * @default 0.5
 * @range 0, 1
 */
uniform float u_reflectionFalloff;

/**
 * Brightness of the key-light highlights.
 * @label Highlight
 * @default 0.8
 * @range 0, 1.5
 */
uniform float u_highlight;

/**
 * Direction of the key light around the sphere, degrees.
 * @label Light Angle
 * @default 125
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * How much each small ball acts as a lens for what is behind it.
 * @label Ball Lens
 * @default 0.7
 * @range 0, 1
 */
uniform float u_ballLens;

/**
 * Depth of the colour tint of the glass balls, like stained glass: a faint
 * tint at low values, deep saturated glass at high ones. Always transmits.
 * @label Ball Tint
 * @default 0.8
 * @range 0, 2
 */
uniform float u_ballDensity;

// SECTION: Environment
/**
 * Softbox windows in the procedural studio. They show in the reflections
 * and, bent, through the glass, which is what makes the refraction visible.
 * @label Studio Detail
 * @default 0.5
 * @range 0, 1
 */
uniform float u_studioDetail;

/**
 * Optional equirectangular environment image (2:1 panorama).
 * @label Environment Map
 * @assets env
 */
uniform sampler2D u_env;

/**
 * How much the environment image replaces the procedural studio in the
 * reflections on the sphere and the balls. Needs an image.
 * @label Env Reflection
 * @default 0
 * @range 0, 1
 */
uniform float u_envMix;

/**
 * How much the environment image shows through the glass behind the balls,
 * instead of the tinted background. Needs an image.
 * @label Env Through Glass
 * @default 0
 * @range 0, 1
 */
uniform float u_envThrough;

/**
 * Turns the environment image around the sphere, degrees.
 * @label Env Rotation
 * @default 0
 * @range 0, 360
 */
uniform float u_envRotation;

// SECTION: Focus
/**
 * Shallow depth of field: balls away from the focus plane swell and soften
 * like bokeh.
 * @label Depth Of Field
 * @default 0.35
 * @range 0, 1
 */
uniform float u_bokeh;

/**
 * Where the sharp plane sits, from the back of the sphere (-1) to its front
 * (1).
 * @label Focus
 * @default 0.5
 * @range -1, 1
 */
uniform float u_focus;

/**
 * Extra blur for balls behind the focus plane, deeper in the sphere. 1
 * blurs them like the balls in front; higher smears the back wall away.
 * @label Back Blur
 * @default 1.6
 * @range 0, 4
 */
uniform float u_backBlur;

// SECTION: Balls
/**
 * Number of small balls inside the sphere.
 * @label Count
 * @default 14
 * @range 1, 16
 * @step 1
 */
uniform float u_count;

/**
 * How much of its private room each ball fills. Every ball owns a slot on
 * one of a few rings around the whirl axis; the slots never overlap, so
 * balls can never intersect each other whatever the motion dials do. At 1 a
 * ball fills its slot and has no room left to move; the three balls on the
 * axis are kept a little smaller so they can drift.
 * @label Ball Size
 * @default 0.65
 * @range 0.2, 1
 */
uniform float u_ballSize;

/**
 * How much the ball sizes differ from each other.
 * @label Size Variation
 * @default 0.6
 * @range 0, 1
 */
uniform float u_sizeVariation;

/**
 * Reshuffles where the balls sit and how big each one is.
 * @label Layout Seed
 * @default 7
 * @range 0, 100
 * @step 1
 */
uniform float u_layoutSeed;

// SECTION: Motion
/**
 * Overall animation speed.
 * @label Speed
 * @default 1
 * @range 0, 3
 */
uniform float u_speed;

/**
 * How fast the balls orbit around the sphere's axis.
 * @label Swirl
 * @default 0.6
 * @range 0, 2
 */
uniform float u_swirl;

/**
 * Vortex feel: balls near the axis orbit faster than the outer ones.
 * @label Vortex
 * @default 0.5
 * @range 0, 1
 */
uniform float u_vortex;

/**
 * Up-and-down bobbing of each ball inside its slot.
 * @label Bob
 * @default 0.4
 * @range 0, 1
 */
uniform float u_bob;

/**
 * How freely each ball wanders inside its slot: a slow drift plus a faster
 * jitter, both with their own random rhythm per ball.
 * @label Turbulence
 * @default 0.7
 * @range 0, 1
 */
uniform float u_turbulence;

/**
 * How much of the sphere the flock fills. Scales the whole ring layout,
 * balls included, so they still never touch.
 * @label Spread
 * @default 0.8
 * @range 0.1, 1
 */
uniform float u_spread;

/**
 * Tilt of the whirl axis toward the viewer, degrees.
 * @label Tilt
 * @default 25
 * @range -90, 90
 */
uniform float u_tilt;

// SECTION: Palette
/**
 * Colour-theory scheme the ball colours are drawn from.
 * @label Harmony
 * @select Analogous, Complementary, Split Complementary, Triadic, Tetradic, Monochrome
 * @default 3
 */
uniform float u_harmony;

/**
 * The one colour everything else is derived from: the harmony hues fan out
 * from its hue, and the balls start from its lightness and saturation.
 * @label Key Colour
 * @color
 * @default #ea5a78
 */
uniform vec3 u_keyColor;

/**
 * Reshuffles which harmony hue each ball gets. Spin to randomise the colours.
 * @label Colour Seed
 * @default 3
 * @range 0, 100
 * @step 1
 */
uniform float u_colorSeed;

/**
 * How wide the harmony fans out around each of its hues.
 * @label Hue Spread
 * @default 0.4
 * @range 0, 1
 */
uniform float u_hueSpread;

/**
 * Colourfulness of the balls relative to the key colour. 0 keeps it, -1 is
 * grey, 1 doubles it.
 * @label Saturation
 * @default 0
 * @range -1, 1
 */
uniform float u_saturation;

/**
 * Lightness of the balls relative to the key colour.
 * @label Brightness
 * @default 0
 * @range -1, 1
 */
uniform float u_brightness;

/**
 * Per-ball jitter of lightness and saturation.
 * @label Variation
 * @default 0.5
 * @range 0, 1
 */
uniform float u_variation;

/**
 * Which harmony hue tints the background inside the sphere.
 * @label Background Hue
 * @select Base, Complement, Random
 * @default 1
 */
uniform float u_bgHueMode;

/**
 * How strongly the background is tinted with that hue.
 * @label Background Tint
 * @default 0.18
 * @range 0, 1
 */
uniform float u_bgTint;

/**
 * Lightness of the background inside the sphere. 1 is bright white glass,
 * 0 is a dark smoked sphere.
 * @label Background Brightness
 * @default 0.92
 * @range 0, 1
 */
uniform float u_bgBrightness;

// 16 is a hard ceiling from the Metal compiler: the ball loops are fully
// unrolled up to 16 iterations and keep the ball array in registers; at 17
// the array falls into memory and the whole shader runs four times slower.
const int MAX_BALLS = 16;
const float TAU = 6.28318530718;
const float CAMERA_DIST = 5.0;

// ---------------------------------------------------------------- colour --

vec3 toGamma(vec3 c) {
  return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

vec3 unoklab(vec3 lab) {
  const mat3 m1 = mat3(+1.000000000, +1.000000000, +1.000000000,
      +0.396337777, -0.105561346, -0.089484178,
      +0.215803757, -0.063854173, -1.291485548);
  const mat3 m2 = mat3(+4.076724529, -1.268143773, -0.004111989,
      -3.307216883, +2.609332323, -0.703476310,
      +0.230759054, -0.341134429, +1.706862569);
  vec3 lms = m1 * lab;
  return m2 * (lms * lms * lms);
}

vec3 toLinear(vec3 c) {
  return pow(c, vec3(2.2));
}

vec3 oklab(vec3 lin) {
  const mat3 im1 = mat3(0.4121656120, 0.2118591070, 0.0883097947,
      0.5362752080, 0.6807189584, 0.2818474174,
      0.0514575653, 0.1074065790, 0.6302613616);
  const mat3 im2 = mat3(+0.2104542553, +1.9779984951, +0.0259040371,
      +0.7936177850, -2.4285922050, +0.7827717662,
      -0.0040720468, +0.4505937099, -0.8086757660);
  vec3 lms = im1 * lin;
  return im2 * (sign(lms) * pow(abs(lms), vec3(1.0 / 3.0)));
}

// The key colour as OKLCH: x = lightness, y = chroma, z = hue in degrees.
vec3 keyLch() {
  vec3 lab = oklab(toLinear(u_keyColor));
  return vec3(lab.x, length(lab.yz), degrees(atan(lab.z, lab.y)));
}

bool inGamut(vec3 lin) {
  return max(max(lin.r, lin.g), lin.b) <= 1.0 && min(min(lin.r, lin.g), lin.b) >= 0.0;
}

// Pull an out-of-gamut OKLab colour back by reducing chroma only, so hue and
// lightness (the harmony) survive.
vec3 fitGamut(vec3 lab) {
  vec3 lin = unoklab(lab);
  if (inGamut(lin)) {
    return lin;
  }
  lab.x = clamp(lab.x, 0.0, 1.0);
  float lo = 0.0;
  float hi = 1.0;
  for (int i = 0; i < 6; i++) {
    float mid = 0.5 * (lo + hi);
    if (inGamut(unoklab(vec3(lab.x, lab.yz * mid)))) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return clamp(unoklab(vec3(lab.x, lab.yz * lo)), 0.0, 1.0);
}

// Linear RGB from OKLCH (lightness, chroma, hue in degrees), chroma-fitted.
vec3 oklch(float l, float c, float hueDeg) {
  float h = radians(hueDeg);
  return fitGamut(vec3(l, c * cos(h), c * sin(h)));
}

// Cheaper OKLCH for the per-ball colours: one chroma fallback instead of the
// bisection, since these run per pixel.
vec3 oklchFast(float l, float c, float hueDeg) {
  float h = radians(hueDeg);
  vec2 ab = c * vec2(cos(h), sin(h));
  vec3 lin = unoklab(vec3(l, ab));
  if (!inGamut(lin)) {
    lin = unoklab(vec3(l, ab * 0.6));
  }
  return clamp(lin, 0.0, 1.0);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Four hashes of one seed in a single vector op (the ball loop runs once per
// ball per pixel, so its body is kept as small as possible; sin() is a fast
// hardware intrinsic on the GPUs this runs on, cheaper than trig-free hashes).
vec4 hash4(vec2 p) {
  vec4 q = vec4(p.x * 127.1 + p.y * 311.7) + vec4(0.0, 1553.5, 5697.2, 9843.9);
  return fract(sin(q) * 43758.5453);
}

// Hue offset (degrees) of harmony slot 0..3 for the selected scheme.
float harmonyOffset(float slot, float fan) {
  if (u_harmony < 0.5) {
    return (slot - 1.5) * fan;
  }
  if (u_harmony < 1.5) {
    return slot < 2.0 ? 0.0 : 180.0;
  }
  if (u_harmony < 2.5) {
    return slot < 1.0 ? 0.0 : (slot < 2.0 ? 150.0 : (slot < 3.0 ? 210.0 : 0.0));
  }
  if (u_harmony < 3.5) {
    return slot < 1.0 ? 0.0 : (slot < 2.0 ? 120.0 : (slot < 3.0 ? 240.0 : 0.0));
  }
  if (u_harmony < 4.5) {
    return slot * 90.0;
  }
  return 0.0;
}

// How many distinct hues the selected scheme has.
float harmonySlots() {
  if (u_harmony < 0.5) {
    return 4.0;
  }
  if (u_harmony < 1.5) {
    return 2.0;
  }
  if (u_harmony < 2.5) {
    return 3.0;
  }
  if (u_harmony < 3.5) {
    return 3.0;
  }
  if (u_harmony < 4.5) {
    return 4.0;
  }
  return 1.0;
}

vec3 ballColor(float fi) {
  vec2 seed = vec2(fi * 3.17 + 11.0, u_colorSeed * 1.73 + 5.0);
  float hSlot = hash(seed);
  float hJit = hash(seed + 17.0);
  float hLum = hash(seed + 29.0);
  float hChr = hash(seed + 43.0);

  vec3 key = keyLch();
  float fan = mix(10.0, 60.0, u_hueSpread);
  float slot = floor(hSlot * harmonySlots());
  float hue = key.z + harmonyOffset(slot, fan) + (hJit - 0.5) * fan * 0.5;

  float l = key.x + u_brightness * 0.35 + (hLum - 0.5) * 0.3 * u_variation;
  float c = key.y * (1.0 + u_saturation) * (1.0 + (hChr - 0.5) * 0.8 * u_variation);
  return oklchFast(clamp(l, 0.05, 0.98), max(c, 0.0), hue);
}

float backgroundHue() {
  float keyHue = keyLch().z;
  if (u_bgHueMode < 0.5) {
    return keyHue;
  }
  if (u_bgHueMode < 1.5) {
    return keyHue + 180.0;
  }
  float slot = floor(hash(vec2(u_colorSeed * 0.37 + 3.0, 9.0)) * harmonySlots());
  return keyHue + harmonyOffset(slot, mix(10.0, 60.0, u_hueSpread));
}

// ---------------------------------------------------------------- scene ---

mat3 tiltMatrix() {
  float a = radians(u_tilt);
  float c = cos(a);
  float s = sin(a);
  return mat3(1.0, 0.0, 0.0, 0.0, c, s, 0.0, -s, c);
}

// Ball slots. Each ring is (distance from the whirl axis, height, room) in
// units of the flock radius; a ball lives inside a sphere of radius `room`
// around its slot point. The rings are chosen so those spheres are disjoint:
// in the (axis distance, height) half-plane every pair of ring centres is at
// least room_a + room_b apart (which bounds the 3D distance between any two
// points of the two rings from below), neighbouring slots on a ring are at
// least 2 * room apart, and every ring stays inside the unit sphere. The
// test file checks these numbers, so keep them in this form.
const vec3 RING_CENTER = vec3(0.0, 0.0, 0.22);
const vec3 RING_TOP = vec3(0.0, 0.62, 0.2);
const vec3 RING_BOTTOM = vec3(0.0, -0.62, 0.2);
const vec3 RING_UPPER = vec3(0.5, 0.35, 0.24);
const vec3 RING_LOWER = vec3(0.5, -0.35, 0.24);
const vec3 RING_OUTER = vec3(0.78, 0.0, 0.19);
const float RING_SLOTS = 5.0;

// Slot for ball i: xyz = ring (distance, height, room), w = slot angle index.
// Order: the three axis balls first, then the rings interleaved, so the Count
// dial thins the flock evenly instead of emptying one ring at a time.
vec4 ballSlot(float fi) {
  if (fi < 1.0) {
    return vec4(RING_CENTER, 0.0);
  }
  if (fi < 2.0) {
    return vec4(RING_TOP, 0.0);
  }
  if (fi < 3.0) {
    return vec4(RING_BOTTOM, 0.0);
  }
  float j = fi - 3.0;
  float ring = mod(j, 3.0);
  float k = floor(j / 3.0);
  if (ring < 0.5) {
    return vec4(RING_UPPER, k);
  }
  if (ring < 1.5) {
    return vec4(RING_LOWER, k);
  }
  return vec4(RING_OUTER, k);
}

// Circle of confusion (world units) for a ball centred at depth z.
float defocus(float z, float bigRadius) {
  float d = z - u_focus * bigRadius;
  float amount = d < 0.0 ? -d * u_backBlur : d;
  return u_bokeh * 0.18 * amount;
}

// How far out of focus a traced ball is, 0 sharp .. 1 a soft disc.
float softness(vec4 b, float bigRadius) {
  float blur = defocus(b.z, bigRadius);
  return clamp(1.5 * blur / max(b.w - blur, 1e-4), 0.0, 1.0);
}

// Small ball i at time t: xyz = centre (world units), w = radius.
vec4 ball(float fi, float t, float bigRadius, mat3 tilt) {
  vec4 h = hash4(vec2(fi * 7.31 + 3.0, u_layoutSeed * 2.11 + 1.0));
  vec4 g = hash4(vec2(fi * 3.77 + 9.0, u_layoutSeed * 1.37 + 4.0));

  vec4 slot = ballSlot(fi);
  float rho = slot.x;
  float room = slot.z;

  // Each ring turns as a whole (its balls keep their spacing); rings at
  // different distances turn at different rates, the lower ring lags the
  // upper so the two slide past each other, and every ring breathes: it
  // speeds up and slows down on its own slow rhythm.
  float ringSeed = hash(vec2(rho * 13.0 + slot.y * 7.0, u_layoutSeed * 0.53 + 2.0));
  float rate = u_swirl * mix(1.0, 1.6 - rho, u_vortex) * (slot.y < 0.0 ? 0.8 : 1.0);
  float wobble = 0.4 * sin(t * (0.12 + 0.18 * ringSeed) + ringSeed * TAU);
  float ang = ringSeed * TAU + slot.w * TAU / RING_SLOTS + t * rate * (1.0 + wobble);
  vec3 pos = vec3(rho * cos(ang), slot.y, rho * sin(ang));

  // Balls on the axis have no ring to ride, so leave them more room to drift.
  float axisShrink = rho < 0.01 ? 0.72 : 1.0;
  float radius = room * axisShrink * u_ballSize * mix(1.0, mix(0.45, 1.0, h.w), u_sizeVariation);

  // Wander inside the slot, never further than the room left around the
  // ball: a slow three-axis drift with random rhythms per ball, a faster
  // jitter, and the bob on top.
  vec3 drift = sin(t * (vec3(0.25, 0.2, 0.3) + vec3(0.4, 0.35, 0.4) * h.xyz) + g.xyz * TAU);
  vec3 jitter = 0.35 * sin(t * (vec3(1.4, 1.1, 1.6) + vec3(1.2, 1.3, 0.9) * g.yzw) + h.yzx * TAU);
  vec3 wander = u_turbulence * (drift + jitter);
  wander.y += u_bob * sin(t * (0.6 + g.w) + h.z * TAU);
  wander /= max(1.0, length(wander));
  pos += wander * (room - radius) * 0.95;

  float scale = bigRadius * u_spread;
  pos = tilt * (pos * scale);
  return vec4(pos, radius * scale);
}

// Nearest forward hit of a sphere, or -1.
float sphereHit(vec3 ro, vec3 rd, vec3 c, float r) {
  vec3 oc = ro - c;
  float b = dot(oc, rd);
  float cc = dot(oc, oc) - r * r;
  float disc = b * b - cc;
  if (disc < 0.0) {
    return -1.0;
  }
  float th = -b - sqrt(disc);
  return th > 0.0 ? th : -1.0;
}

// Result of a ball lookup. index is -1 when nothing was hit.
struct Hit {
  float t;
  float index;
  vec4 ball;
};

// Nearest small ball along the ray. Balls are precomputed once per pixel so
// this loop is only sphere tests, and the hit ball is copied out here because
// ES 1.00 fragment shaders cannot index an array with a computed value.
Hit nearestBall(vec4 balls[MAX_BALLS], vec3 ro, vec3 rd, float skip) {
  Hit h;
  h.t = 1e9;
  h.index = -1.0;
  h.ball = vec4(0.0);
  for (int i = 0; i < MAX_BALLS; i++) {
    float fi = float(i);
    if (fi < u_count && fi != skip) {
      float th = sphereHit(ro, rd, balls[i].xyz, balls[i].w);
      if (th > 0.0 && th < h.t) {
        h.t = th;
        h.index = fi;
        h.ball = balls[i];
      }
    }
  }
  return h;
}

vec3 lightDir() {
  float a = radians(u_lightAngle);
  return normalize(vec3(cos(a), sin(a), 0.9));
}

// One soft rectangular light seen in direction `dir`, centred at the given
// azimuth / elevation (degrees) with the given angular half-size.
float softbox(vec2 azEl, vec2 centre, vec2 halfSize) {
  vec2 d = abs(azEl - centre);
  d.x = min(d.x, 360.0 - d.x);
  vec2 inside = 1.0 - smoothstep(halfSize * 0.7, halfSize, d);
  return inside.x * inside.y;
}

// Three softbox windows around the key light: the structure the glass bends.
float softboxes(vec3 dir) {
  vec2 azEl = vec2(degrees(atan(dir.x, -dir.z)), degrees(asin(clamp(dir.y, -1.0, 1.0))));
  float keyAz = u_lightAngle - 90.0;
  float w = softbox(azEl, vec2(keyAz, 30.0), vec2(22.0, 28.0));
  w += 0.7 * softbox(azEl, vec2(keyAz + 110.0, 10.0), vec2(14.0, 40.0));
  w += 0.5 * softbox(azEl, vec2(keyAz - 130.0, -5.0), vec2(30.0, 12.0));
  return w;
}

// Equirectangular environment image lookup. Image samplers are Y-flipped.
vec3 envImage(vec3 dir) {
  float az = atan(dir.x, -dir.z) + radians(u_envRotation);
  vec2 uv = vec2(fract(az / TAU + 0.5), 0.5 + asin(clamp(dir.y, -1.0, 1.0)) / 3.14159265);
  uv.y = 1.0 - uv.y;
  return texture2D(u_env, uv).rgb;
}

// Studio the glass reflects: dim floor, bright sky, key light, softboxes.
vec3 studioEnv(vec3 dir, vec3 bgLo) {
  float sky = smoothstep(-0.6, 0.8, dir.y);
  vec3 c = mix(bgLo * 0.75, vec3(1.0), sky);
  float spot = pow(max(dot(dir, lightDir()), 0.0), 20.0);
  return c + spot * 0.9 + softboxes(dir) * u_studioDetail * 0.8;
}

// The studio with the environment image blended in. Used for the sphere's
// main reflection only: every image lookup is a latency stall in a shader
// this register-heavy, so the small balls reflect the procedural studio.
vec3 studioEnvImage(vec3 dir, vec3 bgLo) {
  vec3 c = studioEnv(dir, bgLo);
  if (u_envMix > 0.001) {
    c = mix(c, envImage(dir) * 1.15, u_envMix);
  }
  return c;
}

// The background that fills the inside of the big sphere: the tint
// gradient with the softboxes faintly in it, optionally the image itself.
vec3 bgEnv(vec3 dir, vec3 bgHi, vec3 bgLo, float detail) {
  float v = smoothstep(-0.9, 0.9, dir.y);
  vec3 c = mix(bgLo, bgHi, v);
  float glow = pow(max(dot(dir, lightDir()), 0.0), 3.0);
  c += glow * 0.18 * bgHi;
  c *= 1.0 - detail * 0.3 + softboxes(dir) * detail * 0.45;
  if (u_envThrough > 0.001) {
    c = mix(c, envImage(dir) * mix(vec3(1.0), bgHi, 0.35), u_envThrough);
  }
  return c;
}

// From inside the big sphere, leave through the back face and look at the
// background. TIR rays bounce back and pick up the far background instead.
vec3 exitEnv(vec3 ro, vec3 rd, float ior, float bigRadius, vec3 bgHi, vec3 bgLo, float detail) {
  float b = dot(ro, rd);
  float cc = dot(ro, ro) - bigRadius * bigRadius;
  float th = -b + sqrt(max(b * b - cc, 0.0));
  vec3 p = ro + rd * th;
  vec3 n = normalize(p);
  vec3 outDir = refract(rd, -n, ior);
  if (dot(outDir, outDir) < 0.5) {
    outDir = reflect(rd, -n);
  }
  float thickness = clamp(th / (2.0 * bigRadius), 0.0, 1.0);
  return bgEnv(outDir, bgHi, bgLo, detail) * mix(0.93, 1.0, thickness);
}

// Where a ray enters a small ball, bends through it and leaves again.
struct Lens {
  vec3 n;
  float chord;
  vec3 e;
  vec3 rdOut;
};

Lens lensThrough(vec3 ro, vec3 rd, vec4 b, float th, float lensScale) {
  Lens l;
  vec3 q = ro + rd * th;
  l.n = (q - b.xyz) / b.w;
  float ballIor = 1.0 + u_ballLens * 0.5 * lensScale;
  vec3 rdIn = refract(rd, l.n, 1.0 / ballIor);
  if (dot(rdIn, rdIn) < 0.5) {
    rdIn = rd;
  }
  l.chord = 2.0 * b.w * max(dot(-rdIn, l.n), 0.0);
  l.e = q + rdIn * l.chord;
  vec3 ne = (l.e - b.xyz) / b.w;
  l.rdOut = refract(rdIn, -ne, ballIor);
  if (dot(l.rdOut, l.rdOut) < 0.5) {
    l.rdOut = rdIn;
  }
  return l;
}

// A small ball's surface: what is behind it tinted by its gel colour, a rim
// of studio reflection and a key-light highlight.
// `b` is the ball as traced (its radius already grown by the circle of
// confusion); `tintScale` softens the tint of balls seen through others.
vec3 ballSurface(vec3 ro, vec3 rd, Lens l, vec4 b, float bigRadius, vec3 col, vec3 behind,
    vec3 bgLo, float tintScale) {
  // Beer-Lambert through coloured glass: the path length through the ball
  // (0 at the rim, 1 through the centre) scales the tint depth.
  float path = clamp(l.chord / (2.0 * b.w), 0.0, 1.0);
  vec3 transmit = pow(max(col, vec3(0.02)), vec3(u_ballDensity * 1.5 * path * tintScale));
  vec3 result = behind * transmit + col * (1.0 - transmit) * 0.12;

  // Bokeh: the ball was traced with its radius grown by the circle of
  // confusion; fade its edge across that band so it reads as out of focus,
  // and let its rim reflection and highlight melt away the same way.
  float blur = max(defocus(b.z, bigRadius), 1e-4);
  float trueR = b.w - blur;
  float soft = softness(b, bigRadius);

  float facing = max(dot(-rd, l.n), 0.0);
  float fres = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
  result = mix(result, studioEnv(reflect(rd, l.n), bgLo), fres * u_reflection * 0.55 * (1.0 - 0.7 * soft));

  vec3 oc = ro - b.xyz;
  float along = dot(oc, rd);
  float dist = sqrt(max(dot(oc, oc) - along * along, 0.0));
  float cover = 1.0 - smoothstep(trueR - blur, trueR + blur, dist);

  vec3 h = normalize(lightDir() - rd);
  float sharpness = 90.0 / (1.0 + 8.0 * blur / max(trueR, 1e-4));
  float spec = pow(max(dot(l.n, h), 0.0), sharpness) * (sharpness / 90.0);
  result += spec * u_highlight * 0.8;
  return mix(behind, result, cover);
}

// A ball seen through another ball: no further lookups behind it.
vec3 shadeBallFar(vec4 b, vec3 col, vec3 ro, vec3 rd, float th, float ior, float bigRadius,
    vec3 bgHi, vec3 bgLo, float detail) {
  Lens l = lensThrough(ro, rd, b, th, 1.0 - 0.7 * softness(b, bigRadius));
  vec3 behind = exitEnv(l.e, l.rdOut, ior, bigRadius, bgHi, bgLo, detail);
  return ballSurface(ro, rd, l, b, bigRadius, col, behind, bgLo, 0.6);
}

// One colour channel's view into the sphere. The near and far balls were
// found once with the green ray; here the channel's own (differently bent)
// ray is intersected against just those two, which is what smears the ball
// edges into colour fringes while keeping the search loops out of the
// per-channel work. A channel ray that slips past the ball sees the
// background, as it would past the ball's rim.
vec3 traceChannel(vec3 p1, vec3 n1, vec3 rd, float ior, float bigRadius, vec3 bgHi, vec3 bgLo,
    float detail, Hit near, vec3 nearCol, Hit far, vec3 farCol) {
  vec3 rdIn = refract(rd, n1, 1.0 / ior);
  if (dot(rdIn, rdIn) < 0.5) {
    rdIn = rd;
  }
  vec3 ro = p1 + rdIn * 1e-4;
  if (near.index < 0.0) {
    return exitEnv(ro, rdIn, ior, bigRadius, bgHi, bgLo, detail);
  }
  float th = sphereHit(ro, rdIn, near.ball.xyz, near.ball.w);
  if (th < 0.0) {
    return exitEnv(ro, rdIn, ior, bigRadius, bgHi, bgLo, detail);
  }
  Lens l = lensThrough(ro, rdIn, near.ball, th, 1.0 - 0.7 * softness(near.ball, bigRadius));
  vec3 behind;
  float thFar = far.index < 0.0 ? -1.0 : sphereHit(l.e, l.rdOut, far.ball.xyz, far.ball.w);
  if (thFar > 0.0) {
    behind = shadeBallFar(far.ball, farCol, l.e, l.rdOut, thFar, ior, bigRadius, bgHi, bgLo, detail);
  } else {
    behind = exitEnv(l.e, l.rdOut, ior, bigRadius, bgHi, bgLo, detail);
  }
  return ballSurface(ro, rdIn, l, near.ball, bigRadius, nearCol, behind, bgLo, 1.0);
}

void main() {
  vec2 res = u_resolution;
  float shortSide = min(res.x, res.y);
  vec2 p = (gl_FragCoord.xy - 0.5 * res) / (0.5 * shortSide);
  float t = u_time * u_speed;
  float bigRadius = u_size;

  // Silhouette of the sphere on the screen plane under mild perspective.
  float screenRadius = bigRadius * CAMERA_DIST / sqrt(CAMERA_DIST * CAMERA_DIST - bigRadius * bigRadius);
  float edgePx = (length(p) - screenRadius) * 0.5 * shortSide;
  float cover = 1.0 - smoothstep(-0.75, 0.75, edgePx);
  if (cover <= 0.0) {
    gl_FragColor = vec4(u_outside, u_outsideOpacity);
    return;
  }

  // Palette for the inside of the sphere.
  float bgHue = backgroundHue();
  float bgL = mix(0.25, 0.97, u_bgBrightness);
  float bgC = u_bgTint * 0.11;
  vec3 bgHi = oklch(bgL, bgC, bgHue);
  vec3 bgLo = oklch(max(bgL - 0.16, 0.05), bgC * 1.7, bgHue);

  // Pull the anti-aliased rim pixels just inside the silhouette so their
  // rays still hit the sphere.
  vec3 ro = vec3(0.0, 0.0, CAMERA_DIST);
  vec2 pc = p * min(1.0, screenRadius * 0.999 / max(length(p), 1e-5));
  vec3 rd = normalize(vec3(pc, 0.0) - ro);
  float th = sphereHit(ro, rd, vec3(0.0), bigRadius);
  if (th < 0.0) {
    th = -dot(ro, rd);
  }
  vec3 p1 = ro + rd * th;
  vec3 n1 = normalize(p1);

  if (u_ripple > 0.0) {
    vec3 q = p1 * (u_rippleScale * 5.0 / bigRadius);
    vec3 wobble = vec3(
        sin(q.y * 1.3 + t * 0.8 + q.z),
        sin(q.x * 1.1 - t * 0.6 + q.z * 0.7),
        sin(q.x * 0.9 + q.y * 0.8 + t * 0.5));
    n1 = normalize(n1 + wobble * u_ripple * 0.35);
  }

  // Lay out the balls once; the three channel traces share them.
  vec4 balls[MAX_BALLS];
  mat3 tilt = tiltMatrix();
  for (int i = 0; i < MAX_BALLS; i++) {
    vec4 b = vec4(0.0, 0.0, 0.0, -1.0);
    if (float(i) < u_count) {
      b = ball(float(i), t, bigRadius, tilt);
      b.w += defocus(b.z, bigRadius);
    }
    balls[i] = b;
  }

  float ior = 1.0 + u_refraction * 0.6;
  float spread = u_aberration * 0.08 * (0.4 + u_refraction);

  // Reflection falloff: 1 at the rim, fading to (1 - falloff) at the centre.
  float facing = max(dot(-rd, n1), 0.0);
  float rimMask = mix(1.0, pow(1.0 - facing, 2.5), u_reflectionFalloff);
  float detail = u_studioDetail * rimMask;

  // Find the nearest ball, and the ball behind it through its lens, once.
  vec3 rdG = refract(rd, n1, 1.0 / ior);
  if (dot(rdG, rdG) < 0.5) {
    rdG = rd;
  }
  vec3 roG = p1 + rdG * 1e-4;
  Hit near = nearestBall(balls, roG, rdG, -1.0);
  Hit far;
  far.index = -1.0;
  far.t = 1e9;
  far.ball = vec4(0.0);
  vec3 nearCol = vec3(0.0);
  vec3 farCol = vec3(0.0);
  if (near.index >= 0.0) {
    nearCol = ballColor(near.index);
    Lens lg = lensThrough(roG, rdG, near.ball, near.t, 1.0 - 0.7 * softness(near.ball, bigRadius));
    far = nearestBall(balls, lg.e, lg.rdOut, near.index);
    if (far.index >= 0.0) {
      farCol = ballColor(far.index);
    }
  }

  vec3 interior = vec3(
      traceChannel(p1, n1, rd, ior - spread, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).r,
      traceChannel(p1, n1, rd, ior, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).g,
      traceChannel(p1, n1, rd, ior + spread, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).b);

  float f0 = (ior - 1.0) / (ior + 1.0);
  f0 *= f0;
  float fres = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);
  vec3 color = mix(interior, studioEnvImage(reflect(rd, n1), bgLo), fres * u_reflection * rimMask);

  vec3 h = normalize(lightDir() - rd);
  float ndh = max(dot(n1, h), 0.0);
  color += (pow(ndh, 400.0) * 1.2 + pow(ndh, 30.0) * 0.12) * u_highlight * rimMask;

  // Thick glass at the rim: a darker band just inside a thin bright edge.
  float grazing = pow(1.0 - facing, 3.0);
  float rimLine = smoothstep(0.75, 1.0, grazing);
  color *= 1.0 - grazing * 0.35 * u_reflection;
  color += rimLine * 0.6 * u_reflection * studioEnv(n1, bgLo);

  color = toGamma(color);

  // Text backdrop: a screen-space radial gradient above everything.
  float backdropR = length(p) / max(screenRadius * u_backdropSize, 1e-4);
  float backdrop = 1.0 - smoothstep(1.0 - u_backdropSoftness, 1.0, backdropR);
  color = mix(color, u_backdropColor, backdrop * u_backdropOpacity);

  gl_FragColor = vec4(mix(u_outside, color, cover), mix(u_outsideOpacity, 1.0, cover));
}
