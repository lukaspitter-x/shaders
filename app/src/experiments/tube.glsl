/**
 * Tube — a thick, soft 3D tube crossing the viewport edge-to-edge on a dark
 * void, lit by a hotspot that sweeps along its length. The centerline is a
 * wave: `Pos Y + Tilt·x + two sine harmonics`, so the path is always smooth,
 * always crosses the full width, and flexes organically when animated.
 *
 * Lighting model (from the reference): the tube "breathes" between a dim state
 * (deep saturated body, thin crisp rim lines hugging the silhouette) and a
 * bloom state (the body blows out toward the highlight ceiling and the rims
 * dissolve into the glow). One periodic hotspot travels along the tube's
 * length per loop; its proximity drives BOTH the local body bloom and the rim
 * dissolve, so brightness and rim-crispness stay inversely coupled like real
 * light. Path flex, sweep and bloom are all phase-locked to one master loop —
 * seamless at any duration.
 *
 * Camera focus: a movable radial focus field. Inside its radius the tube is
 * sharp; with distance from the focus center everything defocuses — silhouette
 * spreads, rim lines widen and dim — up to the Softness amount.
 *
 * Unified palette: identical contract to Thermal. Every pixel computes an
 * illumination level and samples ONE ramp born from the Key Color, so body,
 * rims, halo and background are hue-matched siblings by construction.
 *
 * Technique: 2.5D analytic cylinder. For a pixel at normalized distance q from
 * the centerline (slope-corrected so thickness holds on tilted sections),
 * z = sqrt(1 - q^2) reconstructs a fake surface normal without raymarching
 * (Pencil-safe). Fresnel `pow(1 - z, k)` is 0 on the front and 1 at the rims.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Color
/**
 * The one hue everything is derived from — body, rims, halo and background are
 * all ramped brightness/temperature siblings of this.
 * @label Key Color
 * @color
 * @default #1f6bff
 */
uniform vec3 u_key;

// SECTION: Color
/**
 * Analogous hue drift across the light gradient (warmer where the light is,
 * cooler away). 0 = strict monochrome; higher = juicier.
 * @label Hue Spread
 * @default 0.25
 * @range 0, 1
 */
uniform float u_hueSpread;

// SECTION: Color
/**
 * Highlight ceiling — caps how bright any tone (body bloom, rim, halo) can
 * get, so nothing blows out to white and the image never feels overblown. Low
 * keeps a moody, saturated look; high lets highlights climb toward near-white.
 * @label Highlight Ceiling
 * @default 0.6
 * @range 0.2, 1
 */
uniform float u_highlightCap;

// SECTION: Color
/**
 * Saturation of the highlights. Low lets bright tones wash toward white; high
 * keeps them vividly in the key hue (brightening by scaling the colour up
 * instead of adding white), so ceiled highlights stay colourful rather than grey.
 * @label Highlight Saturation
 * @default 0.35
 * @range 0, 1
 */
uniform float u_highlightSat;

// SECTION: Tube
/**
 * Diameter of the tube as a fraction of viewport height.
 * @label Thickness
 * @default 0.55
 * @range 0.1, 1.2
 */
uniform float u_thickness;

// SECTION: Tube
/**
 * Vertical position of the tube's centerline.
 * @label Pos Y
 * @default 0
 * @range -1, 1
 */
uniform float u_posY;

// SECTION: Tube
/**
 * End-to-end slope — tilts the whole tube so it enters low and exits high
 * (or vice versa) while still spanning the full width.
 * @label Tilt
 * @default 0
 * @range -1, 1
 */
uniform float u_tilt;

// SECTION: Tube
/**
 * Amplitude of the path's wave — 0 is a straight tube, higher bends it into
 * the S-curve and beyond.
 * @label Curve Amount
 * @default 0.4
 * @range 0, 1
 */
uniform float u_curveAmt;

// SECTION: Tube
/**
 * How many bends fit across the viewport — low is one lazy S, high packs in
 * tighter serpentine waves.
 * @label Curve Scale
 * @default 0.75
 * @range 0.25, 3
 */
uniform float u_curveScale;

// SECTION: Tube
/**
 * Slides the wave shape horizontally along the tube, picking which part of the
 * S lands mid-frame.
 * @label Curve Phase
 * @default 0
 * @range -1, 1
 */
uniform float u_curvePhase;

// SECTION: Tube
/**
 * Second wave harmonic — adds an asymmetric, more organic wobble on top of the
 * main curve. 0 = a clean single wave.
 * @label Curve Detail
 * @default 0.3
 * @range 0, 1
 */
uniform float u_curveDetail;

// SECTION: Light
/**
 * Seconds for one full cycle — the light sweeping once along the tube, the
 * body breathing dim→bloom→dim, and the path flexing — all phase-locked.
 * The loop is seamless at any value.
 * @label Loop Duration
 * @default 10
 * @range 2, 30
 */
uniform float u_loopDur;

// SECTION: Light
/**
 * Length of tube the travelling hotspot lights up at once — narrow is a local
 * glint gliding along the arc, wide washes most of the tube so the whole body
 * breathes together.
 * @label Sweep Width
 * @default 0.6
 * @range 0.1, 1.5
 */
uniform float u_sweepWidth;

// SECTION: Light
/**
 * Phase-shifts the light sweep relative to the path flex, as a fraction of the
 * loop — decides where along the arc the hotspot sits when the curve is mid-
 * flex, without breaking the seamless loop.
 * @label Light Offset
 * @default 0
 * @range -0.5, 0.5
 */
uniform float u_lightOffset;

// SECTION: Light
/**
 * How hard the body blows out where the hotspot passes — 0 keeps the tube at
 * its dim level throughout; high washes it toward the Highlight Ceiling and
 * dissolves the rim lines into the glow.
 * @label Bloom
 * @default 0.75
 * @range 0, 1.5
 */
uniform float u_bloomAmt;

// SECTION: Light
/**
 * Body brightness at the dim end of the breath — the saturated floor the tube
 * falls back to between hotspot passes.
 * @label Body Level
 * @default 0.45
 * @range 0, 1
 */
uniform float u_bodyLevel;

// SECTION: Light
/**
 * Brightness of the rim highlight lines hugging the tube's silhouette.
 * @label Rim Intensity
 * @default 1.2
 * @range 0, 3
 */
uniform float u_rimIntensity;

// SECTION: Light
/**
 * How far the rim light reaches inward from the silhouette — thin crisp lines
 * vs broad bands bleeding toward the tube's core.
 * @label Rim Width
 * @default 0.35
 * @range 0.05, 1
 */
uniform float u_rimWidth;

// SECTION: Focus
/**
 * Horizontal position of the camera-focus center.
 * @label Focus X
 * @default 0
 * @range -1, 1
 */
uniform float u_focusX;

// SECTION: Focus
/**
 * Vertical position of the camera-focus center.
 * @label Focus Y
 * @default 0
 * @range -1, 1
 */
uniform float u_focusY;

// SECTION: Focus
/**
 * Radius of the in-focus zone around the focus center — inside it the tube is
 * sharp. Shrink it toward 0 to defocus the whole frame (the reference look);
 * grow it to pull the entire tube into focus.
 * @label Focus Size
 * @default 0.35
 * @range 0, 2
 */
uniform float u_focusSize;

// SECTION: Focus
/**
 * Width of the transition ring from sharp to fully defocused — small snaps
 * from crisp to blurry, large eases the blur in gradually.
 * @label Focus Falloff
 * @default 0.7
 * @range 0.05, 2
 */
uniform float u_focusFalloff;

// SECTION: Focus
/**
 * Maximum defocus outside the focus zone — how dreamy the out-of-focus tube
 * gets: silhouette spreads, rim lines widen and dim. 0 disables the effect.
 * @label Softness
 * @default 0.65
 * @range 0, 1
 */
uniform float u_softness;

// SECTION: Atmosphere
/**
 * How much the path undulates over the loop — the S-curve flexing its bends.
 * 0 freezes the path; the light keeps sweeping.
 * @label Flex Amount
 * @default 0.3
 * @range 0, 1
 */
uniform float u_flexAmt;

// SECTION: Atmosphere
/**
 * Halo bleeding off the silhouette into the dark void — how far the tube's
 * light spills into the background.
 * @label Glow Spill
 * @default 0.5
 * @range 0, 2
 */
uniform float u_glowSpill;

// SECTION: Atmosphere
/**
 * Lift of the void itself — 0 is true black; higher tints the background with
 * a faint key-hued ambience so the tube sits in air, not on paper.
 * @label Void Lift
 * @default 0.12
 * @range 0, 1
 */
uniform float u_voidLift;

vec3 toLinear(vec3 c) {
  return pow(c, vec3(2.2));
}

vec3 toGamma(vec3 c) {
  return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

// iq's branchless rgb<->hsv, used only for the Hue Spread drift.
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

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// The single palette every pixel samples: illumination t in 0..~1.2 maps from a
// near-black shadow (still tinted by the key hue) through the key to a
// near-white highlight — the same contract as Thermal, so the two shaders'
// palettes are interchangeable siblings.
vec3 palette(float t, vec3 keyLin) {
  t = clamp(t, 0.0, 1.2);
  vec3 shadow = keyLin * 0.02;
  vec3 mid = keyLin;
  vec3 hi = mix(mix(keyLin, vec3(1.0), 0.55), clamp(keyLin * 2.2, 0.0, 1.0), u_highlightSat);
  vec3 peak = mix(mix(keyLin, vec3(1.0), 0.9), clamp(keyLin * 3.2, 0.0, 1.0), u_highlightSat);
  if (t < 0.5) return mix(shadow, mid, smoothstep(0.0, 0.5, t));
  if (t < 1.0) return mix(mid, hi, smoothstep(0.5, 1.0, t));
  return mix(hi, peak, smoothstep(1.0, 1.2, t));
}

// Soft highlight ceiling: near-linear below `ceil`, smoothly saturating toward
// it so no tone blows out to white.
float softClip(float t, float ceil) {
  float x = t / ceil;
  return ceil * x / pow(1.0 + x * x * x, 1.0 / 3.0);
}

// The tube's centerline y (in p-units, full height == 1) at horizontal nx in
// [-1,1], plus its analytic slope for thickness correction. `flex` is the
// loop phase in radians (integer cycles per loop → seamless).
vec2 centerline(float nx, float flex) {
  float w1 = 3.1415927 * u_curveScale;
  // Incommensurate second harmonic so the wobble never mirrors the main wave.
  float w2 = 2.3 * w1;
  float a1 = u_curveAmt * 0.35;
  float a2 = u_curveDetail * a1 * 0.6;
  // Flex animates the harmonics' phases in counter-motion (not a travelling
  // wave), so the bends lean and recover in place like the reference.
  float ph1 = u_curvePhase * 3.1415927 + u_flexAmt * 0.8 * sin(flex);
  float ph2 = 1.7 - u_flexAmt * 1.1 * sin(flex + 1.3);
  float y = u_posY * 0.5 + u_tilt * 0.35 * nx + a1 * sin(w1 * nx + ph1) + a2 * sin(w2 * nx + ph2);
  float dy = u_tilt * 0.35 + a1 * w1 * cos(w1 * nx + ph1) + a2 * w2 * cos(w2 * nx + ph2);
  return vec2(y, dy);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;

  // Centered, aspect-corrected coords: full viewport height == 1 unit.
  vec2 p = uv - 0.5;
  p.x *= aspect;
  // Horizontal coord spanning exactly [-1, 1] across the width, aspect-free —
  // the tube's length parameter.
  float nx = 2.0 * uv.x - 1.0;

  // --- Master loop: one phase drives flex, sweep and breathing ---
  float phase = fract(u_time / max(u_loopDur, 0.1));
  float flex = phase * 6.2831853;

  // --- Signed distance to the centerline, slope-corrected ---
  vec2 cl = centerline(nx, flex);
  // Vertical offset shortened by the local slope ≈ true distance to the curve,
  // so thickness holds steady on tilted/bent sections.
  float slopeP = cl.y * 2.0 / aspect;
  float halfT = max(u_thickness, 0.02) * 0.5;
  float q = (p.y - cl.x) / sqrt(1.0 + slopeP * slopeP) / halfT;
  float aq = abs(q);

  // Fake cylinder normal: z is 1 on the tube's spine, 0 at the silhouette.
  float z = sqrt(max(1.0 - q * q, 0.0));

  // --- Camera focus: radial blur field ---
  // Sharp inside the focus radius, easing to full Softness across the falloff
  // ring. beta is the local defocus amount every edge width scales off.
  vec2 focusC = vec2(u_focusX * 0.5 * aspect, u_focusY * 0.5);
  float fd = length(p - focusC);
  float beta = u_softness * smoothstep(u_focusSize * 0.5, u_focusSize * 0.5 + max(u_focusFalloff, 0.05) * 0.5, fd);

  // --- The travelling hotspot (single light source) ---
  // Periodic along the tube with period P > the visible span, so the hotspot
  // glides off one edge, crosses a dark gap (the dim half of the breath) and
  // re-enters the other side — a seamless one-directional loop. Sweep Width
  // sets the gaussian reach; wide values wash the whole tube at pass-center.
  float sigma = 0.25 + 0.9 * u_sweepWidth;
  float P = 2.4 + 5.0 * sigma;
  float xh = (fract(phase + u_lightOffset) - 0.5) * P;
  float dw = (fract((nx - xh) / P + 0.5) - 0.5) * P;
  float L = exp(-dw * dw / (2.0 * sigma * sigma));

  // --- Tube illumination ---
  // Body: a dim cylinder-shaded floor plus the local bloom where the hotspot
  // passes. Bloom pushes toward (and past) the palette's highlight band; the
  // Highlight Ceiling soft-clips it so it never hard-blows to white.
  float body = u_bodyLevel * (0.30 + 0.45 * z);
  float bloom = u_bloomAmt * L * (0.55 + 0.45 * z);

  // Rims: Fresnel lines at the silhouette. Defocus (beta) widens the falloff
  // exponent and dims the peak — crisp thin lines in focus, dissolving bands
  // out of focus. The hotspot ALSO widens/dims them (rims melt into the body
  // bloom near the light), keeping brightness and crispness inversely coupled.
  float dissolve = 1.0 + 2.5 * beta + 1.2 * u_bloomAmt * L;
  float rimP = mix(14.0, 3.5, u_rimWidth) / dissolve;
  float rim = pow(1.0 - z, rimP) * u_rimIntensity * (0.55 + 0.65 * L) / (1.0 + 1.6 * beta + 0.8 * u_bloomAmt * L);

  float tTube = body + bloom + rim;

  // --- The void: near-black key-tinted air + the tube's spilled halo ---
  // The halo hugs the silhouette (crisp when in focus) and reaches farther,
  // softer, with defocus — the out-of-focus tube smears into the dark.
  float haloReach = 0.10 + 0.35 * u_glowSpill + 0.45 * beta;
  float halo = exp(-max(aq - 1.0, 0.0) / max(haloReach, 1.0e-3));
  float tVoid = u_voidLift * 0.10 + halo * (0.25 + 0.75 * L) * u_glowSpill * (0.35 + 0.4 * u_bodyLevel + 0.5 * u_bloomAmt);

  // Highlight ceiling: soft-limit every tone so nothing blows out to white.
  float tCeil = mix(0.6, 1.2, u_highlightCap);
  tTube = softClip(tTube, tCeil);
  tVoid = softClip(tVoid, tCeil);

  // --- Silhouette mask, defocus-widened ---
  // In focus the edge is a couple of pixels; out of focus it spreads both ways
  // so the silhouette genuinely loses its line, not just its rim light.
  float px = 1.0 / (halfT * u_resolution.y);
  float bw = 1.5 * px + 0.9 * beta;
  float alpha = 1.0 - smoothstep(1.0 - bw * 0.4, 1.0 + bw, aq);

  float t = mix(tVoid, tTube, alpha);

  // --- Shade through the ONE palette ---
  vec3 keyLin = toLinear(u_key);
  vec3 col = palette(t, keyLin);

  // Hue Spread: subtle analogous drift, warmer toward the hotspot and the lit
  // core — applied to tube and void alike so they stay hue-matched.
  float lit = alpha * (0.5 * L + 0.3 * z) + (1.0 - alpha) * 0.3 * halo * L;
  vec3 hsv = rgb2hsv(col);
  hsv.x = fract(hsv.x + u_hueSpread * 0.05 * (lit - 0.35));
  col = hsv2rgb(hsv);

  col = toGamma(col);

  // Dither to kill banding in the long soft gradients.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
