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
 * Colour harmony: ball colours are not picked directly. A base hue, a
 * harmony scheme and a seed generate an OKLCH palette (analogous, triadic,
 * tetradic, ...), so every combination stays in tune. The sphere's inner
 * background is a pale tint from the same harmony. Spin the seeds to
 * randomise colours or layout without leaving the scheme.
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

// SECTION: Glass
/**
 * How strongly the sphere bends what is inside it. 0 is flat window glass,
 * 1 is a dense crystal ball.
 * @label Distortion
 * @default 0.45
 * @range 0, 1
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
 * @default 0.5
 * @range 0, 1
 */
uniform float u_ballLens;

/**
 * How dense the colour of the small balls is. Low is a faint tinted bubble,
 * high is a saturated gel ball.
 * @label Ball Density
 * @default 0.6
 * @range 0, 1
 */
uniform float u_ballDensity;

// SECTION: Balls
/**
 * Number of small balls inside the sphere.
 * @label Count
 * @default 18
 * @range 1, 24
 * @step 1
 */
uniform float u_count;

/**
 * Radius of the small balls relative to the big sphere.
 * @label Ball Size
 * @default 0.13
 * @range 0.02, 0.35
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
 * Up-and-down bobbing of each ball.
 * @label Bob
 * @default 0.4
 * @range 0, 1
 */
uniform float u_bob;

/**
 * Random jitter layered on top of the orbit.
 * @label Turbulence
 * @default 0.3
 * @range 0, 1
 */
uniform float u_turbulence;

/**
 * How far the balls roam from the centre of the sphere.
 * @label Spread
 * @default 0.75
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
 * Hue the harmony is built around, degrees on the OKLCH wheel.
 * @label Base Hue
 * @default 20
 * @range 0, 360
 */
uniform float u_baseHue;

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
 * Colourfulness of the balls.
 * @label Saturation
 * @default 0.8
 * @range 0, 1
 */
uniform float u_saturation;

/**
 * Lightness of the balls.
 * @label Brightness
 * @default 0.7
 * @range 0, 1
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

const int MAX_BALLS = 24;
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

  float fan = mix(10.0, 60.0, u_hueSpread);
  float slot = floor(hSlot * harmonySlots());
  float hue = u_baseHue + harmonyOffset(slot, fan) + (hJit - 0.5) * fan * 0.5;

  float l = mix(0.4, 0.92, u_brightness) + (hLum - 0.5) * 0.3 * u_variation;
  float c = u_saturation * 0.2 * (1.0 + (hChr - 0.5) * 0.8 * u_variation);
  return oklchFast(clamp(l, 0.05, 0.98), max(c, 0.0), hue);
}

float backgroundHue() {
  if (u_bgHueMode < 0.5) {
    return u_baseHue;
  }
  if (u_bgHueMode < 1.5) {
    return u_baseHue + 180.0;
  }
  float slot = floor(hash(vec2(u_colorSeed * 0.37 + 3.0, 9.0)) * harmonySlots());
  return u_baseHue + harmonyOffset(slot, mix(10.0, 60.0, u_hueSpread));
}

// ---------------------------------------------------------------- scene ---

mat3 tiltMatrix() {
  float a = radians(u_tilt);
  float c = cos(a);
  float s = sin(a);
  return mat3(1.0, 0.0, 0.0, 0.0, c, s, 0.0, -s, c);
}

// Small ball i at time t: xyz = centre (world units), w = radius.
vec4 ball(float fi, float t, float bigRadius, mat3 tilt) {
  vec2 seed = vec2(fi * 7.31 + 3.0, u_layoutSeed * 2.11 + 1.0);
  float h1 = hash(seed);
  float h2 = hash(seed + 5.0);
  float h3 = hash(seed + 13.0);
  float h4 = hash(seed + 23.0);
  float h5 = hash(seed + 37.0);

  float radius = u_ballSize * bigRadius * mix(1.0, mix(0.4, 1.5, h5), u_sizeVariation);
  float usable = max(bigRadius - radius * 1.05, 0.0);

  float rho = mix(0.15, 1.0, h1);
  float rate = u_swirl * mix(1.0, 1.6 - rho, u_vortex);
  float ang = h3 * TAU + t * rate;
  float y = (h2 * 2.0 - 1.0) * 0.85 + u_bob * 0.35 * sin(t * (0.6 + h4) + h3 * TAU);

  vec3 pos = vec3(rho * cos(ang), y, rho * sin(ang)) * u_spread;
  pos += u_turbulence * 0.18 * vec3(
      sin(t * 1.7 + h4 * 9.0),
      cos(t * 1.3 + h1 * 7.0),
      sin(t * 1.1 + h2 * 5.0));

  pos = pos / max(1.0, length(pos)) * usable;
  pos = tilt * pos;
  return vec4(pos, radius);
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

// Soft studio the glass reflects: dim floor, bright sky, one key light.
vec3 studioEnv(vec3 dir, vec3 bgLo) {
  float sky = smoothstep(-0.6, 0.8, dir.y);
  vec3 c = mix(bgLo * 0.75, vec3(1.0), sky);
  float spot = pow(max(dot(dir, lightDir()), 0.0), 20.0);
  return c + spot * 0.9;
}

// The background that fills the inside of the big sphere.
vec3 bgEnv(vec3 dir, vec3 bgHi, vec3 bgLo) {
  float v = smoothstep(-0.9, 0.9, dir.y);
  vec3 c = mix(bgLo, bgHi, v);
  float glow = pow(max(dot(dir, lightDir()), 0.0), 3.0);
  return c + glow * 0.18 * bgHi;
}

// From inside the big sphere, leave through the back face and look at the
// background. TIR rays bounce back and pick up the far background instead.
vec3 exitEnv(vec3 ro, vec3 rd, float ior, float bigRadius, vec3 bgHi, vec3 bgLo) {
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
  return bgEnv(outDir, bgHi, bgLo) * mix(0.93, 1.0, thickness);
}

// Where a ray enters a small ball, bends through it and leaves again.
struct Lens {
  vec3 n;
  float chord;
  vec3 e;
  vec3 rdOut;
};

Lens lensThrough(vec3 ro, vec3 rd, vec4 b, float th) {
  Lens l;
  vec3 q = ro + rd * th;
  l.n = (q - b.xyz) / b.w;
  float ballIor = 1.0 + u_ballLens * 0.5;
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
vec3 ballSurface(vec3 rd, Lens l, float radius, vec3 col, vec3 behind, vec3 bgLo) {
  float density = u_ballDensity * 1.4 * l.chord / radius;
  vec3 transmit = pow(max(col, vec3(0.001)), vec3(density));
  vec3 result = behind * transmit + col * (1.0 - transmit) * 0.3;

  float facing = max(dot(-rd, l.n), 0.0);
  float fres = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
  result = mix(result, studioEnv(reflect(rd, l.n), bgLo), fres * u_reflection);

  vec3 h = normalize(lightDir() - rd);
  float spec = pow(max(dot(l.n, h), 0.0), 90.0);
  return result + spec * u_highlight * 0.8;
}

// A ball seen through another ball: no further lookups behind it.
vec3 shadeBallFar(vec4 b, vec3 col, vec3 ro, vec3 rd, float th, float ior, float bigRadius,
    vec3 bgHi, vec3 bgLo) {
  Lens l = lensThrough(ro, rd, b, th);
  vec3 behind = exitEnv(l.e, l.rdOut, ior, bigRadius, bgHi, bgLo);
  return ballSurface(rd, l, b.w, col, behind, bgLo);
}

// One colour channel's view into the sphere. The near and far balls were
// found once with the green ray; here the channel's own (differently bent)
// ray is intersected against just those two, which is what smears the ball
// edges into colour fringes while keeping the search loops out of the
// per-channel work. A channel ray that slips past the ball sees the
// background, as it would past the ball's rim.
vec3 traceChannel(vec3 p1, vec3 n1, vec3 rd, float ior, float bigRadius, vec3 bgHi, vec3 bgLo,
    Hit near, vec3 nearCol, Hit far, vec3 farCol) {
  vec3 rdIn = refract(rd, n1, 1.0 / ior);
  if (dot(rdIn, rdIn) < 0.5) {
    rdIn = rd;
  }
  vec3 ro = p1 + rdIn * 1e-4;
  if (near.index < 0.0) {
    return exitEnv(ro, rdIn, ior, bigRadius, bgHi, bgLo);
  }
  float th = sphereHit(ro, rdIn, near.ball.xyz, near.ball.w);
  if (th < 0.0) {
    return exitEnv(ro, rdIn, ior, bigRadius, bgHi, bgLo);
  }
  Lens l = lensThrough(ro, rdIn, near.ball, th);
  vec3 behind;
  float thFar = far.index < 0.0 ? -1.0 : sphereHit(l.e, l.rdOut, far.ball.xyz, far.ball.w);
  if (thFar > 0.0) {
    behind = shadeBallFar(far.ball, farCol, l.e, l.rdOut, thFar, ior, bigRadius, bgHi, bgLo);
  } else {
    behind = exitEnv(l.e, l.rdOut, ior, bigRadius, bgHi, bgLo);
  }
  return ballSurface(rdIn, l, near.ball.w, nearCol, behind, bgLo);
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
    balls[i] = ball(float(i), t, bigRadius, tilt);
  }

  float ior = 1.0 + u_refraction * 0.6;
  float spread = u_aberration * 0.08 * (0.4 + u_refraction);

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
    Lens lg = lensThrough(roG, rdG, near.ball, near.t);
    far = nearestBall(balls, lg.e, lg.rdOut, near.index);
    if (far.index >= 0.0) {
      farCol = ballColor(far.index);
    }
  }

  vec3 interior = vec3(
      traceChannel(p1, n1, rd, ior - spread, bigRadius, bgHi, bgLo, near, nearCol, far, farCol).r,
      traceChannel(p1, n1, rd, ior, bigRadius, bgHi, bgLo, near, nearCol, far, farCol).g,
      traceChannel(p1, n1, rd, ior + spread, bigRadius, bgHi, bgLo, near, nearCol, far, farCol).b);

  float facing = max(dot(-rd, n1), 0.0);
  float f0 = (ior - 1.0) / (ior + 1.0);
  f0 *= f0;
  float fres = f0 + (1.0 - f0) * pow(1.0 - facing, 5.0);
  vec3 color = mix(interior, studioEnv(reflect(rd, n1), bgLo), fres * u_reflection);

  vec3 h = normalize(lightDir() - rd);
  float ndh = max(dot(n1, h), 0.0);
  color += (pow(ndh, 400.0) * 1.2 + pow(ndh, 30.0) * 0.12) * u_highlight;

  // Thick glass at the rim: a darker band just inside a thin bright edge.
  float grazing = pow(1.0 - facing, 3.0);
  float rimLine = smoothstep(0.75, 1.0, grazing);
  color *= 1.0 - grazing * 0.35 * u_reflection;
  color += rimLine * 0.6 * u_reflection * studioEnv(n1, bgLo);

  color = toGamma(color);
  gl_FragColor = vec4(mix(u_outside, color, cover), mix(u_outsideOpacity, 1.0, cover));
}
