/**
 * Tube — a thick, soft 3D tube crossing the viewport edge-to-edge on a dark
 * void, lit by a hotspot that sweeps along its length. The centerline is a
 * wave: `Pos Y + Tilt·x + two sine harmonics`, so the path is always smooth,
 * always crosses the full width, and flexes organically when animated. The
 * primary harmonic can be waveshaped — leaned sideways and flattened toward
 * plateaus — for bend styles beyond a pure sine.
 *
 * Lighting model (from the reference): the tube "breathes" between a dim state
 * (deep saturated body, thin crisp rim lines hugging the silhouette) and a
 * bloom state (the body blows out toward the highlight ceiling and the rims
 * dissolve into the glow). One periodic hotspot travels along the tube's
 * length per loop; its proximity drives BOTH the local body bloom and the rim
 * dissolve, so brightness and rim-crispness stay inversely coupled like real
 * light. Path motion (flex, travel, sway), sweep and bloom are all phase-
 * locked to one master loop — seamless at any duration.
 *
 * Camera focus: a movable radial focus field. Inside its radius the tube is
 * sharp; with distance from the focus center everything defocuses — silhouette
 * spreads, rim lines widen and dim — up to the Softness amount. Dispersion
 * rides on it: each colour channel sees a slightly different tube radius, and
 * the split grows with defocus, so rims and halo fringe warm↔cool exactly
 * where a real lens would.
 *
 * Unified palette: identical contract to Thermal. Every pixel computes an
 * illumination level and samples ONE ramp born from the Key Color, so body,
 * rims, halo and background are hue-matched siblings by construction — the
 * dispersion channels are genuine palette samples too, never invented hues.
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
 * Hue drift of the LIT tones (bloom, hotspot, bright halo) away from the key.
 * Positive walks toward the key's warm neighbour (violet for a blue key),
 * negative toward the cool one (cyan). 0 keeps lit tones strictly on-key.
 * @label Hue Lit
 * @default 0.25
 * @range -1, 1
 */
uniform float u_hueSpread;

// SECTION: Color
/**
 * Hue drift of the SHADOW tones (dim body, void glow) — same signed scale as
 * Hue Lit. Give it the opposite sign for a classic warm-light/cool-shadow
 * split, or the same sign to push the whole gradient one way.
 * @label Hue Shadow
 * @default -0.15
 * @range -1, 1
 */
uniform float u_hueShadow;

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
 * End-to-end slope. Gentle values lean the tube; at full tilt it runs steeper
 * than corner-to-corner, entering and exiting through the top/bottom edges —
 * always cropped by the viewport either way.
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
 * Leans the bends sideways — crests sweep left or right like a wave about to
 * break, instead of rising and falling symmetrically.
 * @label Curve Lean
 * @default 0
 * @range -1, 1
 */
uniform float u_curveLean;

// SECTION: Tube
/**
 * Shape of the bends — 0 is a pure sine; higher flattens the crests toward
 * plateaus with tighter turns between them, for a more architectural path.
 * @label Curve Sharpness
 * @default 0
 * @range 0, 1
 */
uniform float u_curveSharp;

// SECTION: Tube
/**
 * Second wave harmonic — adds an asymmetric, more organic wobble on top of the
 * main curve. 0 = a clean single wave.
 * @label Curve Detail
 * @default 0.3
 * @range 0, 1
 */
uniform float u_curveDetail;

// SECTION: Tube
/**
 * Frequency of the detail wobble relative to the main curve — low keeps it a
 * broad secondary swell, high makes it a fine ripple riding the big bends.
 * @label Detail Scale
 * @default 2.3
 * @range 1.2, 4
 */
uniform float u_detailScale;

// SECTION: Light
/**
 * Seconds for one full cycle — the light sweeping once along the tube, the
 * body breathing dim→bloom→dim, and the path moving — all phase-locked.
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
 * Phase-shifts the light sweep relative to the path motion, as a fraction of
 * the loop — decides where along the arc the hotspot sits when the curve is
 * mid-flex, without breaking the seamless loop.
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
 * Base brightness of the rim highlight lines along the whole tube,
 * independent of the sweep. The sweep-riding flare is Rim Flare.
 * @label Rim Intensity
 * @default 1.2
 * @range 0, 3
 */
uniform float u_rimIntensity;

// SECTION: Light
/**
 * Brightness of the sweep-riding rim — the flanks that flare before and
 * after the hotspot (at Rim Lead distance), independent of the base Rim
 * Intensity. 0 = the rim ignores the sweep entirely.
 * @label Rim Flare
 * @default 0.7
 * @range 0, 3
 */
uniform float u_rimFlare;

// SECTION: Light
/**
 * How much the BASE rim rides the true hotspot. Positive concentrates the
 * base rim where the light is; 0 keeps it even along the whole tube;
 * negative dims it under the hotspot so it glows in the dark stretches.
 * The flanking flare is separate (Rim Flare + Rim Lead).
 * @label Rim Sweep
 * @default 0.35
 * @range -1, 1
 */
uniform float u_rimFollow;

// SECTION: Light
/**
 * Distance of the bright rim's flanks from the hotspot. The rim flares BOTH
 * before and after the sweep — announcing it and trailing it — handing off
 * to the dark rim directly under the light. 0 locks rim and sweep together.
 * @label Rim Lead
 * @default 0.2
 * @range 0, 1
 */
uniform float u_rimLead;

// SECTION: Light
/**
 * A dark counter-rim carved in under the hotspot — as the sweep arrives the
 * silhouette edges darken below the body while the middle blooms (limb
 * darkening under frontal light), so the lit stretch reads bright-middle /
 * dark-edges. 0 = off.
 * @label Rim Shadow
 * @default 0.3
 * @range 0, 1
 */
uniform float u_rimShadow;

// SECTION: Light
/**
 * Brightness of the dark rim — 0 lets it crush to true black under the
 * sweep, 1 rests it on a clearly visible key-tinted shadow level
 * (independent of Body Level), above 1 it lifts further into a bright
 * saturated band (it never darkens the tube past its own level, so on a dim
 * body high values read through the dye instead).
 * @label Shadow Floor
 * @default 1
 * @range 0, 2
 */
uniform float u_shadowFloor;

// SECTION: Light
/**
 * Saturation of the dark rim — 0 leaves it on the palette's neutral shadow
 * (dark, hue barely present); 1 dyes it a deep, fully saturated key tone so
 * the darkened edges stay vividly in the key colour.
 * @label Shadow Saturation
 * @default 0.5
 * @range 0, 1
 */
uniform float u_shadowTint;

// SECTION: Light
/**
 * How far the rim light reaches inward from the silhouette — thin crisp lines
 * vs broad bands bleeding toward the tube's core.
 * @label Rim Width
 * @default 0.35
 * @range 0.05, 1
 */
uniform float u_rimWidth;

// SECTION: Motion
/**
 * Master motion — scales all path movement (flex, travel, sway) together.
 * 0 freezes the path completely; the light keeps sweeping.
 * @label Motion Amount
 * @default 1
 * @range 0, 1.5
 */
uniform float u_motion;

// SECTION: Motion
/**
 * In-place flex — the bends lean and recover where they stand, like the
 * reference. The wave shape breathes without going anywhere.
 * @label Flex Amount
 * @default 0.3
 * @range 0, 1
 */
uniform float u_flexAmt;

// SECTION: Motion
/**
 * Traveling wave — slides the wave pattern along the tube so the bends
 * migrate across the frame, one wavelength per loop (always seamless).
 * @label Travel
 * @default 0.15
 * @range 0, 1
 */
uniform float u_travel;

// SECTION: Motion
/**
 * Whole-tube bob — the entire path drifts up and down once per loop, on top
 * of whatever the bends themselves are doing.
 * @label Sway
 * @default 0
 * @range 0, 1
 */
uniform float u_sway;

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

// SECTION: Focus
/**
 * Chromatic dispersion — each colour channel sees a slightly different tube
 * radius, so rims and halo fringe warm↔cool like light through real glass.
 * The split rides the focus blur exclusively: in-focus areas stay perfectly
 * clean and the fringe grows with defocus (needs Softness > 0 to appear).
 * Every channel is a genuine palette sample — no new hues.
 * @label Dispersion
 * @default 0.3
 * @range 0, 2
 */
uniform float u_dispersion;

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

// Shade a per-channel illumination triple through the ONE palette. Each channel
// is a genuine palette sample, so the only way colours separate is Dispersion
// feeding slightly different levels per channel (a spatial offset upstream).
// On sharp features (the rim) that separation fringes into the key's analogous
// neighbours — violet inside, cyan outside for a blue key — the same pairing
// real longitudinal CA produces, so it reads as lens glass, not rainbow.
vec3 shadeRGB(vec3 t, vec3 keyLin) {
  return vec3(
    palette(t.x, keyLin).r,
    palette(t.y, keyLin).g,
    palette(t.z, keyLin).b
  );
}

// Soft highlight ceiling: near-linear below `ceil`, smoothly saturating toward
// it so no tone blows out to white.
float softClip(float t, float ceil) {
  float x = t / ceil;
  return ceil * x / pow(1.0 + x * x * x, 1.0 / 3.0);
}

// Waveshaped sine and its d/dθ: `lean` skews the crests sideways (a wave about
// to break), `sharp` flattens them toward plateaus. lean=sharp=0 collapses to
// plain (sin, cos).
vec2 shapedSin(float th, float lean, float sharp) {
  float t2 = th - lean * sin(th);
  float dt2 = 1.0 - lean * cos(th);
  float s = sin(t2);
  float den = 1.0 + sharp * abs(s);
  float v = s * (1.0 + sharp) / den;
  float dv = cos(t2) * (1.0 + sharp) / (den * den) * dt2;
  return vec2(v, dv);
}

// The tube's centerline y (in p-units, full height == 1) at horizontal nx in
// [-1,1], plus its analytic slope for thickness correction. `flex` is the
// loop phase in radians (integer cycles per loop → seamless). Motion is a mix
// of a standing flex (phases wobble in counter-motion, bends lean in place)
// and a traveling wave (phase advances one full cycle per loop, bends migrate)
// — each seamless on its own, so any blend of them is too.
vec2 centerline(float nx, float flex) {
  float w1 = 3.1415927 * u_curveScale;
  float w2 = u_detailScale * w1;
  float a1 = u_curveAmt * 0.35;
  float a2 = u_curveDetail * a1 * 0.6;
  float lean = u_curveLean * 0.8;
  float sharp = u_curveSharp * 3.0;
  float m = u_motion;
  float phBase = u_curvePhase * 3.1415927;
  // Blend factor toward the traveling wave. Time-constant, so seamlessness is
  // preserved; scaled by the master so Motion 0 truly freezes the path.
  float mixT = clamp(u_travel * m, 0.0, 1.0);

  vec2 h1s = shapedSin(w1 * nx + phBase + m * u_flexAmt * 0.8 * sin(flex), lean, sharp);
  vec2 h1t = shapedSin(w1 * nx + phBase - flex, lean, sharp);
  vec2 h1 = mix(h1s, h1t, mixT);

  float th2s = w2 * nx + 1.7 - m * u_flexAmt * 1.1 * sin(flex + 1.3);
  float th2t = w2 * nx + 1.7 - flex;
  vec2 h2 = mix(vec2(sin(th2s), cos(th2s)), vec2(sin(th2t), cos(th2t)), mixT);

  float sway = m * u_sway * 0.12 * sin(flex);
  // Tilt slope: near-linear when gentle (old feel preserved), ramping up to
  // ~1.25 height-per-half-width at full tilt — steeper than corner-to-corner,
  // so a fully tilted tube crosses the top/bottom edges instead.
  float tiltSlope = u_tilt * (0.35 + 0.9 * abs(u_tilt));
  float y = u_posY * 0.5 + tiltSlope * nx + a1 * h1.x + a2 * h2.x + sway;
  float dy = tiltSlope + a1 * w1 * h1.y + a2 * w2 * h2.y;
  return vec2(y, dy);
}

// Full illumination level for one colour channel at normalized tube distance q:
// cylinder body + bloom + rim inside, spilled halo outside, blended across the
// defocus-widened silhouette and soft-clipped to the highlight ceiling.
// Dispersion calls this three times with slightly different q per channel.
float shadeT(float q, float L, float Lrim, float beta) {
  float aq = abs(q);
  float z = sqrt(max(1.0 - q * q, 0.0));

  // Body: a dim cylinder-shaded floor plus the local bloom where the hotspot
  // passes. Bloom pushes toward (and past) the palette's highlight band; the
  // Highlight Ceiling soft-clips it so it never hard-blows to white.
  float body = u_bodyLevel * (0.30 + 0.45 * z);
  float bloom = u_bloomAmt * L * (0.55 + 0.45 * z);

  // Rims: Fresnel lines at the silhouette. Defocus (beta) widens the falloff
  // exponent and dims the peak — crisp thin lines in focus, dissolving bands
  // out of focus. The hotspot ALSO widens/dims them (rims melt into the body
  // bloom near the light), keeping brightness and crispness inversely coupled.
  float dissolve = 1.0 + 1.2 * beta + 1.2 * u_bloomAmt * L;
  float rimP = mix(14.0, 3.5, u_rimWidth) / dissolve;
  // Rim Sweep: how the rim rides the hotspot. Positive redistributes the rim's
  // energy toward the lit stretch (dim floor away from it, flare under it);
  // negative carves the rim away under the hotspot so it glows in the dark
  // stretches; 0 is a uniform rim.
  // Two independent rim components: the BASE rim (Rim Intensity, optionally
  // modulated by the true hotspot via Rim Sweep) and the FLARE rim (Rim
  // Flare) riding Lrim — the flanks before/after the sweep. The bloom-melt
  // in the denominator stays on the true L: everything dissolves where the
  // body actually blooms.
  float sweepMul = mix(1.0, 0.12 + 1.75 * L, max(u_rimFollow, 0.0))
                 * (1.0 - max(-u_rimFollow, 0.0) * 0.9 * L);
  float rimLevel = u_rimIntensity * sweepMul + u_rimFlare * Lrim;
  float rim = pow(1.0 - z, rimP) * rimLevel / (1.0 + 0.9 * beta + 0.8 * u_bloomAmt * L);

  float tTube = body + bloom + rim;
  // Rim Shadow: limb darkening under the hotspot. Where the true light is on
  // top, the edges are pulled toward a key-tinted shadow floor (a dark sibling
  // of the body on the same palette — never black). The mask blends the
  // Fresnel coordinate with linear radius so the darkening spreads broadly
  // from the silhouette into the body and reads as shading, not a line.
  float darkMask = pow(clamp(mix(1.0 - z, aq, 0.5), 0.0, 1.0), 1.6);
  // Shadow Floor slides the resting level from a clearly visible key-tinted
  // shadow (1) to true black (0). Mostly independent of Body Level so the
  // floor stays visible even on a very dim body.
  float tFloor = (0.12 + 0.3 * body) * u_shadowFloor;
  tTube = mix(tTube, min(tTube, tFloor), min(u_rimShadow * L * darkMask * 1.4, 1.0));

  // The void: near-black key-tinted air + the tube's spilled halo. The halo
  // hugs the silhouette (crisp when in focus) and reaches farther, softer,
  // with defocus — the out-of-focus tube smears into the dark.
  float haloReach = 0.10 + 0.35 * u_glowSpill + 0.45 * beta;
  float halo = exp(-max(aq - 1.0, 0.0) / max(haloReach, 1.0e-3));
  float tVoid = u_voidLift * 0.10 + halo * (0.25 + 0.75 * L) * u_glowSpill * (0.35 + 0.4 * u_bodyLevel + 0.5 * u_bloomAmt);

  // Highlight ceiling: soft-limit every tone so nothing blows out to white.
  float tCeil = mix(0.6, 1.2, u_highlightCap);
  tTube = softClip(tTube, tCeil);
  tVoid = softClip(tVoid, tCeil);

  // Silhouette mask, defocus-widened. In focus the edge is a couple of pixels;
  // out of focus it spreads both ways so the silhouette genuinely loses its
  // line, not just its rim light.
  float px = 1.0 / (max(u_thickness, 0.02) * 0.5 * u_resolution.y);
  float bw = 1.5 * px + 0.45 * beta;
  float alpha = 1.0 - smoothstep(1.0 - bw * 0.4, 1.0 + bw, aq);

  return mix(tVoid, tTube, alpha);
}

// True progressive defocus: convolve the analytic tube field across q with a
// gaussian whose radius grows with the local blur amount — a genuine blur of
// the image (rims, body and silhouette all smear together), not just wider
// edges. The taps ride on shadeT's procedurally softened base, so the 5-tap
// kernel stays band-free even at large radii. In-focus (rad→0) collapses to a
// single sample.
float blurShadeT(float q, float L, float Lrim, float beta) {
  float rad = 1.2 * beta;
  if (rad < 1.0e-3) return shadeT(q, L, Lrim, beta);
  const int TAPS = 9;
  float sum = 0.0;
  float wsum = 0.0;
  for (int i = 0; i < TAPS; i++) {
    float o = float(i) - 4.0;
    // Per-tap pixel jitter breaks the discrete kernel into fine grain (the
    // dither already sets that texture) instead of visible ghost edges.
    float jj = (hash21(gl_FragCoord.xy + vec2(float(i) * 17.13, 7.7)) - 0.5) * 0.5;
    float gw = exp(-o * o * 0.15);
    sum += shadeT(q + (o + jj) * 0.25 * rad, L, Lrim, beta) * gw;
    wsum += gw;
  }
  return sum / wsum;
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

  // --- Master loop: one phase drives path motion, sweep and breathing ---
  float phase = fract(u_time / max(u_loopDur, 0.1));
  float flex = phase * 6.2831853;

  // --- Signed distance to the centerline, slope-corrected ---
  vec2 cl = centerline(nx, flex);
  // Vertical offset shortened by the local slope ≈ true distance to the curve,
  // so thickness holds steady on tilted/bent sections.
  float slopeP = cl.y * 2.0 / aspect;
  float halfT = max(u_thickness, 0.02) * 0.5;
  float q = (p.y - cl.x) / sqrt(1.0 + slopeP * slopeP) / halfT;

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
  // The rim's copy of the light field: two flanks at ±Rim Lead around the
  // hotspot (max of the two, so the peak never doubles). The rim flares
  // before AND after the sweep while the body bloom and dark rim stay on the
  // true hotspot between them.
  float dwA = (fract((nx - u_rimLead - xh) / P + 0.5) - 0.5) * P;
  float dwB = (fract((nx + u_rimLead - xh) / P + 0.5) - 0.5) * P;
  float Lrim = max(
    exp(-dwA * dwA / (2.0 * sigma * sigma)),
    exp(-dwB * dwB / (2.0 * sigma * sigma))
  );

  // --- Dispersion: per-channel tube radius, defocus-gated ---
  // Each channel shades the tube at a slightly scaled q — blue sees a fatter
  // tube, red a thinner one — so the rim lines and halo edge fringe warm on
  // the inside, cool on the outside, like longitudinal CA in a fast lens.
  // The split is proportional to beta ONLY: in-focus pixels get exactly zero
  // split (no double edge on the sharp silhouette) and the fringe lives
  // purely in the out-of-focus smear, which is where real glass fringes too.
  float dsp = u_dispersion * beta * 0.09;
  vec3 tRGB = vec3(
    blurShadeT(q * (1.0 + dsp), L, Lrim, beta),
    blurShadeT(q, L, Lrim, beta),
    blurShadeT(q * (1.0 - dsp), L, Lrim, beta)
  );

  // --- Shade all channels through the ONE palette ---
  vec3 keyLin = toLinear(u_key);
  vec3 col = shadeRGB(tRGB, keyLin);

  // Hue Lit / Hue Shadow: signed analogous drift at each end of the light
  // gradient. `lit` fades between them around a midtone pivot, so bright and
  // dark tones can each lean warm or cool independently — applied to tube and
  // void alike so they stay hue-matched. Uses the center (green) channel's
  // geometry.
  float aq = abs(q);
  float z = sqrt(max(1.0 - q * q, 0.0));
  float haloReach = 0.10 + 0.35 * u_glowSpill + 0.45 * beta;
  float halo = exp(-max(aq - 1.0, 0.0) / max(haloReach, 1.0e-3));
  float px = 1.0 / (halfT * u_resolution.y);
  float bw = 1.5 * px + 0.9 * beta;
  float alpha = 1.0 - smoothstep(1.0 - bw * 0.4, 1.0 + bw, aq);
  float lit = alpha * (0.5 * L + 0.3 * z) + (1.0 - alpha) * 0.3 * halo * L;
  float litN = smoothstep(0.35, 0.85, lit);
  float darkN = smoothstep(0.35, 0.05, lit);
  vec3 hsv = rgb2hsv(col);
  hsv.x = fract(hsv.x + 0.06 * (u_hueSpread * litN + u_hueShadow * darkN) + 1.0);
  col = hsv2rgb(hsv);

  // Shadow Saturation: dye the dark rim toward a deep, fully saturated key
  // tone (the palette's own dark end is low-saturation by design, so a vivid
  // dark needs its own dye). Uses the center channel's carve mask; brightness
  // of the dye follows Shadow Floor.
  float darkMaskM = pow(clamp(mix(1.0 - z, aq, 0.5), 0.0, 1.0), 1.6);
  float wShadow = min(u_rimShadow * L * darkMaskM * 1.4, 1.0) * alpha;
  vec3 kHsv = rgb2hsv(u_key);
  vec3 shadowDye = toLinear(hsv2rgb(vec3(kHsv.x, 1.0, mix(0.1, 0.5, u_shadowFloor))));
  col = mix(col, shadowDye, wShadow * u_shadowTint);

  col = toGamma(col);

  // Dither to kill banding in the long soft gradients.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
