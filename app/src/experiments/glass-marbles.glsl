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
 * Circle keeps the marble round, sized by the layer's short side. Fill
 * Shape stretches it to the layer's bounds instead, so an oval layer gets
 * an oval marble that meets its edges (with Size at 1).
 * @label Fit
 * @select Circle, Fill Shape
 * @default 0
 */
uniform float u_fit;

/**
 * Radius of the big sphere relative to the layer. 1 touches the layer's
 * edges: the host circle in the workbench, the layer bounds in Pencil.
 * @label Size
 * @default 1
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
 * Colour of the fresnel rim glow on the sphere and, fainter, on each ball.
 * @label Fresnel Colour
 * @color
 * @default #ffffff
 */
uniform vec3 u_fresnelColor;

/**
 * Strength of the fresnel rim glow. 0 turns it off.
 * @label Fresnel
 * @default 0.4
 * @range 0, 2
 */
uniform float u_fresnel;

/**
 * How far the rim glow reaches in from the edge: 0 a thin line, 1 a wide
 * halo.
 * @label Fresnel Width
 * @default 0.4
 * @range 0, 1
 */
uniform float u_fresnelWidth;

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

/**
 * Milky inner scatter of the glass balls. 0 is clear glass that only tints
 * what is behind it; higher adds a soft body glow.
 * @label Ball Haze
 * @default 0.3
 * @range 0, 1
 */
uniform float u_ballHaze;

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
 * like bokeh. 0 keeps every ball sharp.
 * @label Depth Of Field
 * @default 0
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
 * @default 1
 * @range 0, 4
 */
uniform float u_backBlur;

// SECTION: Balls
/**
 * Number of small balls inside the sphere.
 * @label Count
 * @default 14
 * @range 1, 32
 * @step 1
 */
uniform float u_count;

/**
 * How much of its private room each ball fills. Every ball owns a slot on
 * one of a few rings around the whirl axis; the slots never overlap, so up
 * to 1 balls can never intersect each other whatever the motion dials do.
 * At 1 a ball fills its slot and has no room left to move; above 1 balls
 * outgrow their slots and may pass through each other. The three balls on
 * the axis are kept a little smaller so they can drift.
 * @label Ball Size
 * @default 0.75
 * @range 0.2, 2
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
 * Slow nod and precession of the whole flock, so every ball keeps moving,
 * including the three on the axis. A rigid rotation: balls still never
 * touch.
 * @label Tumble
 * @default 0.35
 * @range 0, 1
 */
uniform float u_tumble;

/**
 * Tilt of the whirl axis toward the viewer, degrees.
 * @label Tilt
 * @default 25
 * @range -90, 90
 */
uniform float u_tilt;

// SECTION: Particles
/**
 * Number of particles emitted from the centre of the sphere, spread over
 * two depth layers. 0 turns the emitter off.
 * @label Particle Count
 * @default 240
 * @range 0, 768
 * @step 1
 */
uniform float u_particleCount;

/**
 * Colour of the particles. White glows on a dark sphere, a dark tone reads
 * on a light one.
 * @label Particle Colour
 * @color
 * @default #ffffff
 */
uniform vec3 u_particleColor;

/**
 * Opacity of a particle at full life.
 * @label Particle Opacity
 * @default 0.9
 * @range 0, 1
 */
uniform float u_particleOpacity;

/**
 * Radius of a particle relative to the sphere.
 * @label Particle Size
 * @default 0.02
 * @range 0.004, 0.06
 */
uniform float u_particleSize;

/**
 * How much particle sizes differ from each other.
 * @label Particle Size Variation
 * @default 0.5
 * @range 0, 1
 */
uniform float u_particleSizeVar;

/**
 * Velocity of the particles, in sphere radii per second. A particle that
 * reaches the glass stops there and fades.
 * @label Particle Speed
 * @default 0.35
 * @range 0, 3
 */
uniform float u_particleSpeed;

/**
 * Random per-particle variation of speed.
 * @label Particle Speed Variation
 * @default 0.4
 * @range 0, 1
 */
uniform float u_particleSpeedVar;

/**
 * Seconds from birth at the centre to death.
 * @label Particle Lifetime
 * @default 3
 * @range 0.5, 12
 */
uniform float u_particleLife;

/**
 * How a particle appears at birth: 0 pops in at full strength at the
 * centre, 1 fades in over the first part of its life.
 * @label Particle Fade In
 * @default 0.1
 * @range 0, 1
 */
uniform float u_particleFadeIn;

/**
 * Fraction of the life over which a particle fades out at the end.
 * @label Particle Fade
 * @default 0.5
 * @range 0.05, 1
 */
uniform float u_particleFade;

/**
 * Edge softness of each particle: 0 is a hard dot, 1 a soft glow.
 * @label Particle Softness
 * @default 0.6
 * @range 0, 1
 */
uniform float u_particleSoftness;

/**
 * Ease-out of the flight: 0 flies at a constant speed, 1 shoots out fast
 * and slows toward the end.
 * @label Particle Slowdown
 * @default 0.5
 * @range 0, 1
 */
uniform float u_particleSlowdown;

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
// The first 16 balls are stored in an array (fast: it stays in registers);
// a stored array of more than 16 falls out of registers on Metal and the
// whole shader runs four times slower, so balls 17..32 are recomputed inside
// the searches, behind one uniform branch on Count.
const int MAX_BALLS = 32;
const int HALF_BALLS = 16;
// Particles live on P_LAYERS depth layers, each cut into P_SECTORS angular
// sectors holding P_PER_SECTOR particle slots. A pixel only evaluates the
// sectors around its own angle, and within a sector only the slots whose
// staggered age puts them at the pixel's distance from the centre, so
// hundreds of particles cost about as much as a dozen brute-force ones.
const int P_LAYERS = 2;
const int P_PER_SECTOR = 12;
const float P_SECTORS = 32.0;
const float TAU = 6.28318530718;
const float CAMERA_DIST = 5.0;

// ---------------------------------------------------------------- colour --

// Coloured fresnel rim: linear colour scaled by strength and a falloff whose
// power follows Fresnel Width (thin line .. wide halo).
vec3 fresnelGlow(float facing, float scale) {
  float power = mix(6.0, 1.5, u_fresnelWidth);
  return pow(u_fresnelColor, vec3(2.2)) * u_fresnel * scale * pow(1.0 - facing, power);
}

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

mat3 rotX(float a) {
  float c = cos(a);
  float sn = sin(a);
  return mat3(1.0, 0.0, 0.0, 0.0, c, sn, 0.0, -sn, c);
}

mat3 rotY(float a) {
  float c = cos(a);
  float sn = sin(a);
  return mat3(c, 0.0, -sn, 0.0, 1.0, 0.0, sn, 0.0, c);
}

// Orientation of the whole flock: the tilt, plus a slow nod and precession
// under Tumble. Rigid, so the slot envelopes stay disjoint.
mat3 orientation(float t) {
  float nod = u_tumble * 0.6 * sin(t * 0.23);
  float precess = u_tumble * 0.18 * t;
  return rotY(precess) * rotX(radians(u_tilt) + nod);
}

// Ball slots. Each ring is (distance from the whirl axis, height, room) in
// units of the flock radius; a ball lives inside a sphere of radius `room`
// around its slot point. The rings are chosen so those spheres are disjoint:
// in the (axis distance, height) half-plane every pair of ring centres is at
// least room_a + room_b apart (which bounds the 3D distance between any two
// points of the two rings from below), neighbouring slots on a ring are at
// least 2 * room apart, and every ring stays inside the unit sphere. The
// test file checks these numbers, so keep them in this form.
const vec3 RING_CENTER = vec3(0.0, 0.0, 0.18);
const vec3 RING_TOP = vec3(0.0, 0.66, 0.16);
const vec3 RING_BOTTOM = vec3(0.0, -0.66, 0.16);
const vec3 RING_UPPER = vec3(0.42, 0.38, 0.17);
const vec3 RING_LOWER = vec3(0.42, -0.38, 0.17);
const vec3 RING_EQUATOR = vec3(0.45, 0.0, 0.19);
const vec3 RING_OUTER_UPPER = vec3(0.76, 0.2, 0.15);
const vec3 RING_OUTER_LOWER = vec3(0.76, -0.2, 0.15);
const float RING_SLOTS = 6.0;

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
  float ring = mod(j, 5.0);
  float k = floor(j / 5.0);
  if (ring < 0.5) {
    return vec4(RING_EQUATOR, k);
  }
  if (ring < 1.5) {
    return vec4(RING_UPPER, k);
  }
  if (ring < 2.5) {
    return vec4(RING_OUTER_UPPER, k);
  }
  if (ring < 3.5) {
    return vec4(RING_LOWER, k);
  }
  return vec4(RING_OUTER_LOWER, k);
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
  // The breathing is a bounded speed variation: the angle is the integral
  // of rate * (1 + 0.4 sin(w t + phase)), never a factor on t itself (that
  // would make the flock spin faster and faster).
  float w = 0.12 + 0.18 * ringSeed;
  float breathe = t - (0.4 / w) * cos(w * t + ringSeed * TAU);
  float ang = ringSeed * TAU + slot.w * TAU / RING_SLOTS + rate * breathe;
  vec3 pos = vec3(rho * cos(ang), slot.y, rho * sin(ang));

  // Balls on the axis have no ring to ride, so leave them more room to drift.
  float axisShrink = rho < 0.01 ? 0.72 : 1.0;
  float radius = room * axisShrink * u_ballSize * mix(1.0, mix(0.45, 1.0, h.w), u_sizeVariation);

  // Wander inside the slot, never further than the room left around the
  // ball: a slow three-axis drift with random rhythms per ball, a faster
  // jitter, and the bob on top.
  // Axis balls have no orbit, so their drift runs at twice the tempo.
  float tempo = rho < 0.01 ? 2.0 : 1.0;
  vec3 drift = sin(t * tempo * (vec3(0.25, 0.2, 0.3) + vec3(0.4, 0.35, 0.4) * h.xyz) + g.xyz * TAU);
  vec3 jitter = 0.35 * sin(t * (vec3(1.4, 1.1, 1.6) + vec3(1.2, 1.3, 0.9) * g.yzw) + h.yzx * TAU);
  vec3 wander = u_turbulence * (drift + jitter);
  wander.y += u_bob * sin(t * (0.6 + g.w) + h.z * TAU);
  wander /= max(1.0, length(wander));
  pos += wander * max(room - radius, 0.0) * 0.95;

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

// Result of the ball search. index is -1 when nothing was hit; the ball is
// copied out because ES 1.00 fragment shaders cannot index by a computed
// value (and there is no array to index anyway).
struct Hit {
  float t;
  float index;
  vec4 ball;
};


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

// Plain studio: dim floor, bright sky, key light. Used for the small
// balls' rim reflections, where the softbox windows would not be read.
vec3 studioPlain(vec3 dir, vec3 bgLo) {
  float sky = smoothstep(-0.6, 0.8, dir.y);
  vec3 c = mix(bgLo * 0.75, vec3(1.0), sky);
  float spot = pow(max(dot(dir, lightDir()), 0.0), 20.0);
  return c + spot * 0.9;
}

// Studio the sphere reflects: the plain studio plus the softbox windows.
vec3 studioEnv(vec3 dir, vec3 bgLo) {
  return studioPlain(dir, bgLo) + softboxes(dir) * u_studioDetail * 0.8;
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
  vec3 result = behind * transmit + col * (1.0 - transmit) * 0.4 * u_ballHaze;

  // Bokeh: the ball was traced with its radius grown by the circle of
  // confusion; fade its edge across that band so it reads as out of focus,
  // and let its rim reflection and highlight melt away the same way.
  float blur = max(defocus(b.z, bigRadius), 1e-4);
  float trueR = b.w - blur;
  float soft = softness(b, bigRadius);

  float facing = max(dot(-rd, l.n), 0.0);
  float fres = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
  result = mix(result, studioPlain(reflect(rd, l.n), bgLo), fres * u_reflection * 0.55 * (1.0 - 0.7 * soft));
  result += fresnelGlow(facing, 0.5 * (1.0 - 0.7 * soft));

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



// One colour channel's view into the sphere. The near and far balls were
// found once with the green ray; here the channel's own (differently bent)
// ray is intersected against just those two, which is what smears the ball
// edges into colour fringes while keeping the search loops out of the
// per-channel work. A channel ray that slips past the ball sees the
// background, as it would past the ball's rim.
// A ball seen through another ball: no further lookups behind it.
vec3 shadeBallFar(vec4 b, vec3 col, vec3 ro, vec3 rd, float th, float ior, float bigRadius,
    vec3 bgHi, vec3 bgLo, float detail) {
  Lens l = lensThrough(ro, rd, b, th, 1.0 - 0.7 * softness(b, bigRadius));
  vec3 behind = exitEnv(l.e, l.rdOut, ior, bigRadius, bgHi, bgLo, detail);
  return ballSurface(ro, rd, l, b, bigRadius, col, behind, bgLo, 0.6);
}

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

// Inverse of the flight ease: which age has travelled the fraction `e` of a
// full life's reach. eased = (1 + s) age - s age^2.
float easeInverse(float e, float slow) {
  if (slow < 0.01) {
    return e;
  }
  float b = 1.0 + slow;
  return (b - sqrt(max(b * b - 4.0 * slow * e, 0.0))) / (2.0 * slow);
}

// Everything about one particle sector (angular wedge on one layer) that
// its slots share: speed, time phase, reach.
struct Sector {
  float k;
  float speed;
  float tau;
  float reach;
};

Sector sectorAt(float k, float layerIndex, float t, float life, float bigRadius) {
  Sector sc;
  vec4 hs = hash4(vec2(k * 3.7 + layerIndex * 57.0, u_layoutSeed * 1.91 + 8.0));
  sc.k = k;
  sc.speed = u_particleSpeed * (1.0 + (hs.x - 0.5) * 2.0 * u_particleSpeedVar);
  sc.tau = t / life + hs.y;
  sc.reach = sc.speed * life * bigRadius;
  return sc;
}

// Soft-disc coverage of one particle slot at the three channel crossing
// points q of its layer plane. Ordered so that the cheap tests (alive
// slot, radial distance) run before any hashing.
vec3 particleSlot(Sector sc, float m, float layerIndex, float zL, float layerR,
    float bigRadius, float rbMax, vec2 qR, vec2 qG, vec2 qB) {
  float slots = float(P_SECTORS) * float(P_PER_SECTOR) * float(P_LAYERS);
  // The first (count / capacity) slots of every sector are alive; the
  // fractional remainder is settled per sector.
  float perSector = u_particleCount / slots * float(P_PER_SECTOR);
  if (m + 1.0 - fract(sc.tau * 0.0 + sc.k * 0.618) > perSector) {
    return vec3(0.0);
  }
  float age = fract(sc.tau + m / float(P_PER_SECTOR));
  float eased = mix(age, age * (2.0 - age), u_particleSlowdown);
  float rho = length(qG);
  // Radial early-out with the largest possible size: a particle at the
  // wrong distance from the centre cannot touch this pixel.
  float travelMax = min(eased * sc.reach, layerR * 0.985);
  if (abs(travelMax - rho) > rbMax * 2.0) {
    return vec3(0.0);
  }

  vec4 h = hash4(vec2(sc.k * 3.7 + m * 11.3 + layerIndex * 57.0, u_layoutSeed * 1.37 + 3.0));
  float size = u_particleSize * bigRadius * mix(1.0, mix(0.4, 1.4, h.y), u_particleSizeVar);
  float travel = min(eased * sc.reach, layerR * 0.985 - size);

  float fadeIn = smoothstep(0.0, max(u_particleFadeIn * 0.4, 0.003), age);
  float fadeOut = 1.0 - smoothstep(1.0 - u_particleFade, 1.0, age);
  float alive = fadeIn * fadeOut;
  if (alive < 0.001) {
    return vec3(0.0);
  }

  // Particles are tiny, so cap how far defocus can grow them: it keeps the
  // sector lookup valid.
  float r = size * (0.6 + 0.4 * alive);
  float rb = r + min(defocus(zL, bigRadius), r * 0.4);
  // The lookup widens to four sectors either side near the centre; a
  // particle wider than that is faded until it fits.
  float clear = rb * P_SECTORS / (TAU * 4.0);
  alive *= smoothstep(clear * 0.5, clear, travel);

  float ang = ((sc.k + h.x) / P_SECTORS - 0.5) * TAU + layerIndex * 2.1;
  vec2 c = travel * vec2(cos(ang), sin(ang));
  vec2 dg = qG - c;
  float d2g = dot(dg, dg);
  if (d2g > rb * rb * 2.5) {
    return vec3(0.0);
  }
  float energy = alive * (r * r) / (rb * rb);
  vec3 d2 = vec3(dot(qR - c, qR - c), d2g, dot(qB - c, qB - c));
  vec3 kk = clamp(1.0 - d2 / (rb * rb), 0.0, 1.0);
  vec3 edge = mix(smoothstep(0.0, 0.25, kk), kk * kk, u_particleSoftness);
  return edge * energy;
}

// Accumulate one sector's particles into `cover`.
vec3 sectorCover(vec3 cover, float k, float layerIndex, float zL, float layerR, float t, float life,
    float bigRadius, float rbMax, float rho, float edgeR, vec2 qR, vec2 qG, vec2 qB) {
  float slots = float(P_PER_SECTOR);
  Sector sc = sectorAt(k, layerIndex, t, life, bigRadius);
  if (sc.reach > edgeR && rho > edgeR - rbMax * 2.0) {
    // Particles from this sector pile up against the glass here: any slot
    // can be present.
    for (int m = 0; m < P_PER_SECTOR; m++) {
      vec3 a = particleSlot(sc, float(m), layerIndex, zL, layerR, bigRadius, rbMax, qR, qG, qB);
      cover = cover + a - cover * a;
    }
    return cover;
  }
  // Only the two slots whose staggered age can put them at this radius
  // (slots have no age jitter, so the inverse is exact up to the
  // particle's own radial extent).
  float e = clamp(rho / max(sc.reach, 1e-4), 0.0, 1.0);
  float mReal = fract(easeInverse(e, u_particleSlowdown) - sc.tau) * slots;
  float m1 = floor(mReal);
  vec3 a = particleSlot(sc, mod(m1, slots), layerIndex, zL, layerR, bigRadius, rbMax, qR, qG, qB);
  cover = cover + a - cover * a;
  a = particleSlot(sc, mod(m1 + 1.0, slots), layerIndex, zL, layerR, bigRadius, rbMax, qR, qG, qB);
  return cover + a - cover * a;
}

// Per-channel particle coverage for the three refracted rays, so particles
// near the glass pick up the same colour fringes as everything else.
vec3 particleCover(vec3 p1, vec3 n1, vec3 rd, float ior, float spread, float t, float bigRadius,
    float tMax) {
  vec3 rdR = refract(rd, n1, 1.0 / (ior - spread));
  vec3 rdG = refract(rd, n1, 1.0 / ior);
  vec3 rdB = refract(rd, n1, 1.0 / (ior + spread));
  if (dot(rdG, rdG) < 0.5) {
    rdR = rd;
    rdG = rd;
    rdB = rd;
  }
  float life = max(u_particleLife, 0.05);
  float sizeMax = u_particleSize * bigRadius * 1.4;
  float rbMax = sizeMax * 1.4;
  vec3 cover = vec3(0.0);
  for (int L = 0; L < P_LAYERS; L++) {
    float layerIndex = float(L);
    float zL = (layerIndex - 0.5) * 0.7 * bigRadius;
    float layerR = sqrt(max(bigRadius * bigRadius - zL * zL, 0.0));
    float tG = (zL - p1.z) / min(rdG.z, -1e-4);
    if (tG <= 0.0 || tG > tMax) {
      continue;
    }
    vec2 qG = p1.xy + rdG.xy * tG;
    vec2 qR = p1.xy + rdR.xy * ((zL - p1.z) / min(rdR.z, -1e-4));
    vec2 qB = p1.xy + rdB.xy * ((zL - p1.z) / min(rdB.z, -1e-4));
    float rho = length(qG);
    float theta = atan(qG.y, qG.x) - layerIndex * 2.1;
    float k0 = floor((theta / TAU + 0.5) * P_SECTORS);
    // How many sectors either side a particle here can span (wider near
    // the centre, where sectors are narrow), at most four.
    float reachN = min(ceil(rbMax * P_SECTORS / (TAU * max(rho, 1e-4))), 4.0);
    // Pixels in the thin ring where particles pile up against the glass
    // must check every slot; elsewhere only the slot nominally at this
    // radius and its two neighbours can be here.
    float edgeR = layerR * 0.985 - sizeMax;

    // Most pixels only need the three sectors around their angle; near the
    // centre, where sectors are narrow, widen to nine.
    if (reachN <= 1.0) {
      for (int sIdx = 0; sIdx < 3; sIdx++) {
        float k = mod(k0 + float(sIdx) - 1.0 + P_SECTORS, P_SECTORS);
        cover = sectorCover(cover, k, layerIndex, zL, layerR, t, life, bigRadius, rbMax, rho, edgeR,
            qR, qG, qB);
      }
    } else {
      for (int sIdx = 0; sIdx < 9; sIdx++) {
        float off = float(sIdx) - 4.0;
        if (abs(off) > reachN) {
          continue;
        }
        float k = mod(k0 + off + P_SECTORS * 4.0, P_SECTORS);
        cover = sectorCover(cover, k, layerIndex, zL, layerR, t, life, bigRadius, rbMax, rho, edgeR,
            qR, qG, qB);
      }
    }
  }
  return cover;
}

// A traced ball: its radius grown by the circle of confusion, or a dead
// entry past the Count dial.
vec4 ballAt(float fi, float t, float bigRadius, mat3 tilt) {
  if (fi >= u_count) {
    return vec4(0.0, 0.0, 0.0, -1.0);
  }
  vec4 b = ball(fi, t, bigRadius, tilt);
  b.w += defocus(b.z, bigRadius);
  return b;
}

// Nearest ball along a ray, skipping index `skip`: the stored first 16,
// then, only when Count exceeds 16, the recomputed rest.
Hit searchBalls(vec4 balls[HALF_BALLS], vec3 ro, vec3 rd, float skip, float t, float bigRadius,
    mat3 tilt) {
  Hit h;
  h.t = 1e9;
  h.index = -1.0;
  h.ball = vec4(0.0);
  for (int i = 0; i < HALF_BALLS; i++) {
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
  if (u_count > float(HALF_BALLS)) {
    // Balls 17..32 are recomputed here rather than stored: a stored array
    // of more than 16 falls out of registers on Metal. min(h.t, 0) is 0,
    // but ties these balls to the stored search's result so the compiler
    // cannot hoist them above the branch and keep them live alongside the
    // array (which is the same cliff by another route).
    float t2 = t + min(h.t, 0.0);
    for (int i = HALF_BALLS; i < MAX_BALLS; i++) {
      float fi = float(i);
      if (fi < u_count && fi != skip) {
        vec4 b = ballAt(fi, t2, bigRadius, tilt);
        float th = sphereHit(ro, rd, b.xyz, b.w);
        if (th > 0.0 && th < h.t) {
          h.t = th;
          h.index = fi;
          h.ball = b;
        }
      }
    }
  }
  return h;
}

void main() {
  vec2 res = u_resolution;
  float shortSide = min(res.x, res.y);
  // Fill Shape normalises each axis by its own extent, so the unit circle
  // of the marble maps to the ellipse inscribed in the layer.
  vec2 p = u_fit > 0.5
      ? (gl_FragCoord.xy - 0.5 * res) / (0.5 * res)
      : (gl_FragCoord.xy - 0.5 * res) / (0.5 * shortSide);
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
  mat3 tilt = orientation(t);
  float ior = 1.0 + u_refraction * 0.6;
  float spread = u_aberration * 0.08 * (0.4 + u_refraction);

  // Reflection falloff: 1 at the rim, fading to (1 - falloff) at the centre.
  float facing = max(dot(-rd, n1), 0.0);
  float rimMask = mix(1.0, pow(1.0 - facing, 2.5), u_reflectionFalloff);
  float detail = u_studioDetail * rimMask;

  // Find the nearest ball once with the green ray, recomputing each ball
  // in the loop (see MAX_BALLS).
  vec3 rdG = refract(rd, n1, 1.0 / ior);
  if (dot(rdG, rdG) < 0.5) {
    rdG = rd;
  }
  vec3 roG = p1 + rdG * 1e-4;
  vec4 balls[HALF_BALLS];
  for (int i = 0; i < HALF_BALLS; i++) {
    balls[i] = ballAt(float(i), t, bigRadius, tilt);
  }
  Hit near = searchBalls(balls, roG, rdG, -1.0, t, bigRadius, tilt);
  Hit far;
  far.t = 1e9;
  far.index = -1.0;
  far.ball = vec4(0.0);
  vec3 farCol = vec3(0.0);
  if (near.index >= 0.0) {
    // The ball behind the nearest one, through its lens: this is what makes
    // the balls refract each other.
    Lens lg = lensThrough(roG, rdG, near.ball, near.t, 1.0 - 0.7 * softness(near.ball, bigRadius));
    // min(near.t, 0) is 0, but ties this search to the first one's result
    // so the compiler cannot hoist and merge the recomputed balls.
    far = searchBalls(balls, lg.e, lg.rdOut, near.index, t + min(near.t, 0.0), bigRadius, tilt);
    if (far.index >= 0.0) {
      farCol = ballColor(far.index);
    }
  }
  vec3 nearCol = near.index >= 0.0 ? ballColor(near.index) : vec3(0.0);

  vec3 interior = vec3(
      traceChannel(p1, n1, rd, ior - spread, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).r,
      traceChannel(p1, n1, rd, ior, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).g,
      traceChannel(p1, n1, rd, ior + spread, bigRadius, bgHi, bgLo, detail, near, nearCol, far, farCol).b);

  if (u_particleCount > 0.5) {
    float tMax = near.index >= 0.0 ? near.t : 1e9;
    vec3 pa = particleCover(p1, n1, rd, ior, spread, t, bigRadius, tMax) * u_particleOpacity;
    interior = mix(interior, toLinear(u_particleColor), pa);
  }

  float f0 = (ior - 1.0) / (ior + 1.0);
  f0 *= f0;
  float fres = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);
  vec3 color = mix(interior, studioEnvImage(reflect(rd, n1), bgLo), fres * u_reflection * rimMask);

  vec3 h = normalize(lightDir() - rd);
  float ndh = max(dot(n1, h), 0.0);
  color += (pow(ndh, 400.0) * 1.2 + pow(ndh, 30.0) * 0.12) * u_highlight * rimMask;

  // Coloured fresnel rim glow.
  color += fresnelGlow(facing, 1.0);

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
