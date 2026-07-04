/**
 * Thermal 2 — Thermal with a directional corona: the rim light and diffuse
 * scatter TRACK the travelling stripes instead of glowing evenly. Each rim
 * point probes the light grating in the direction it faces (Light Reach) and
 * responds with adjustable contrast (Light Tracking), so a bright lobe sweeps
 * continuously around the silhouette as the stripes drift — right rim when a
 * light band is right of the ball, top rim as it passes overhead — while the
 * side facing a dark band falls to near-black.
 *
 * Base model — a dark ball against a backdrop wall, lit by a tall softbox that
 * sweeps horizontally right→left behind the camera. The softbox is faked as a
 * single horizontal light term `Lx` that drives BOTH surfaces in sync: the
 * backdrop gets a left↔right brightness gradient, and the ball's rim highlight
 * migrates to the lit side. The ball's front/center stays dark (an eclipse) —
 * only the Fresnel rim catches light.
 *
 * Unified palette: there are no separate "ball colors" and "wall colors". Every
 * pixel computes an illumination level `t`, then samples ONE ramp born from the
 * Key Color — deep shadow (t→0) through the key (t≈0.5) to a near-white highlight
 * (t→1). So shadows, mid-tones and highlights on the ball and the wall are all
 * hue-matched siblings by construction; only the gradient *spread* differs.
 *
 * Technique: 2.5D analytic sphere. For a pixel at normalized radius r in the
 * ball's projected circle, z = sqrt(1 - r^2) reconstructs a fake surface normal
 * without raymarching (Pencil-safe). Fresnel `pow(1 - z, k)` is 0 on the front
 * (dark) and 1 at the silhouette (bright rim).
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Color
/**
 * The one hue everything is derived from — wall, ball, shadows, mid-tones and
 * highlights are all ramped brightness/temperature siblings of this.
 * @label Key Color
 * @color
 * @default #1f6bff
 */
uniform vec3 u_key;

// SECTION: Color
/**
 * Hue drift of the LIT tones (corona lobe, bright stripe, halo) away from the
 * key. Positive walks toward the key's warm neighbour (violet for a blue key),
 * negative toward the cool one (cyan). 0 keeps lit tones strictly on-key.
 * @label Hue Lit
 * @default 0.25
 * @range -1, 1
 */
uniform float u_hueSpread;

// SECTION: Color
/**
 * Hue drift of the SHADOW tones (dark bands, dim rim, dark glow) — same
 * signed scale as Hue Lit. Give it the opposite sign for a classic
 * warm-light/cool-shadow split, or the same sign to push the whole gradient
 * one way.
 * @label Hue Shadow
 * @default -0.15
 * @range -1, 1
 */
uniform float u_hueShadow;

// SECTION: Color
/**
 * Highlight ceiling — caps how bright any tone (bloom, rim, stripe) can get, so
 * nothing blows out to white and the image never feels overblown. Low keeps a
 * moody, saturated look; high lets highlights climb toward near-white.
 * @label Highlight Ceiling
 * @default 0.6
 * @range 0.2, 1
 */
uniform float u_highlightCap;

// SECTION: Color
/**
 * Saturation of the highlights. Low lets bright tones wash toward white; high
 * keeps them vividly in the key hue (brightening by scaling the colour up instead
 * of adding white), so ceiled highlights stay colourful rather than grey.
 * @label Highlight Saturation
 * @default 0.35
 * @range 0, 1
 */
uniform float u_highlightSat;

// SECTION: Ball
/**
 * Radius of the ball as a fraction of viewport half-height.
 * @label Size
 * @default 0.46
 * @range 0.1, 0.95
 */
uniform float u_ballSize;

// SECTION: Ball
/**
 * Horizontal position of the ball center.
 * @label Pos X
 * @default 0
 * @range -1, 1
 */
uniform float u_ballX;

// SECTION: Ball
/**
 * Vertical position of the ball center.
 * @label Pos Y
 * @default 0
 * @range -1, 1
 */
uniform float u_ballY;

// SECTION: Ball
/**
 * Depth toward/away from the viewer. Positive pushes the ball closer (larger,
 * softer corona); negative sinks it back.
 * @label Depth Z
 * @default 0
 * @range -1, 1
 */
uniform float u_ballZ;

// SECTION: Backdrop
/**
 * How dark the dark stripes (troughs) of the wall are. 0 = black.
 * @label Stripe Dark
 * @default 0.5
 * @range 0, 1
 */
uniform float u_wallBright;

// SECTION: Backdrop
/**
 * How bright the light stripes (peaks) of the wall are — push it up to let them
 * climb toward white (subject to the Highlight Ceiling).
 * @label Stripe Light
 * @default 0.5
 * @range 0, 1
 */
uniform float u_stripeLight;

// SECTION: Backdrop
/**
 * Move the wall on its Z axis — forward brightens and flattens it, back darkens
 * and deepens the vignette.
 * @label Backdrop Z
 * @default 0
 * @range -1, 1
 */
uniform float u_backdropZ;

// SECTION: Light
/**
 * Seconds for the softbox to sweep once across (right→left→front) and loop.
 * The loop is seamless at any value.
 * @label Loop Duration
 * @default 12
 * @range 2, 30
 */
uniform float u_loopDur;

// SECTION: Light
/**
 * Width of each band in the light grating. Light and dark bands are always equal
 * width; this sets how wide they are — small = many thin stripes, large = a few
 * wide ones. They all march right→left, driving wall, rim and glows together.
 * @label Stripe Width
 * @default 0.5
 * @range 0.05, 1.5
 */
uniform float u_density;

// SECTION: Light
/**
 * Edge softness of the stripes — 0 is a hard-edged square grating, 1 is a smooth
 * sine gradient. Band widths stay equal either way.
 * @label Stripe Softness
 * @default 0.6
 * @range 0, 1
 */
uniform float u_sweepFalloff;

// SECTION: Light
/**
 * Balances the perceived width of light vs dark bands. The bands are equal by
 * geometry, but the tone curve makes one read wider — nudge this to even them up.
 * Negative widens the light bands; positive widens the dark bands.
 * @label Stripe Balance
 * @default 0
 * @range -0.8, 0.8
 */
uniform float u_stripeBalance;

// SECTION: Light
/**
 * Time-shifts the ball's OWN surface lighting out of sync with the backdrop, as a
 * fraction of the loop. The stripes stay on the backdrop clock; only the ball's
 * rim/corona lead or lag. 0 = in sync; positive = the ball
 * lights up later than the backdrop, negative = earlier.
 * @label Ball Light Delay
 * @default 0
 * @range -0.5, 0.5
 */
uniform float u_lightLag;

// SECTION: Light
/**
 * How strongly the rim and scatter follow the stripes. 0 = the rim glows evenly
 * all round (classic Thermal); 1 = the corona lives only where the silhouette
 * faces a light band — a hot lobe that sweeps around the ball with the grating
 * while the dark-band side drops to near-black.
 * @label Light Tracking
 * @default 0.65
 * @range 0, 1
 */
uniform float u_rimFollow;

// SECTION: Light
/**
 * How far to the side each rim point looks when reading the grating — the lever
 * arm of the tracking. Small keeps the response local (the lobe hugs the stripe
 * overhead); large lets the rim catch stripes well beside the ball, swinging the
 * lobe wider and earlier. With reach beyond the band width the rim can pick up
 * two stripes at once — twin lobes.
 * @label Light Reach
 * @default 0.6
 * @range 0.05, 1.5
 */
uniform float u_rimReach;

// SECTION: Light
/**
 * How far inward from the silhouette the light reaches — thin ring vs broad glow
 * bleeding toward the center.
 * @label Corona Width
 * @default 0.5
 * @range 0, 1
 */
uniform float u_coronaWidth;

// SECTION: Light
/**
 * Linearity of the rim gradient. 0 hugs the silhouette (the sphere's curvature
 * concentrates it at the very edge); higher spreads it into an even, more linear
 * falloff from edge to center instead of a thick edge that drops off fast.
 * @label Corona Linearity
 * @default 0.4
 * @range 0, 1
 */
uniform float u_rimLinear;

// SECTION: Light
/**
 * Master brightness of the corona.
 * @label Corona Intensity
 * @default 1.6
 * @range 0, 4
 */
uniform float u_coronaIntensity;

// SECTION: Light
/**
 * Chromatic dispersion — splits the light ramp per colour channel so bright
 * transitions fringe warm→cool like light through a lens. Fine-tunes realism.
 * @label Dispersion
 * @default 0.3
 * @range 0, 1
 */
uniform float u_dispersion;

// SECTION: Effects
/**
 * Fake emissive material: a self-lit glow on the rim that also spills onto the
 * surrounding wall, independent of the softbox direction.
 * @label Emissive
 * @default 0.35
 * @range 0, 2
 */
uniform float u_emissive;

// SECTION: Effects
/**
 * Fake bloom: the Diffuse Scatter mirrored outward onto the wall — crisp at the
 * silhouette, diffusing progressively as it spreads. Higher = a wider, softer
 * glow that reaches farther and blurs more toward its outer edge. The master
 * amount; Glow Spread / Intensity / Curve / Fill / Delay below refine it.
 * @label Bloom / Glow
 * @default 0.8
 * @range 0, 2
 */
uniform float u_bloom;

// SECTION: Effects
/**
 * Reach of the ball's glow on the wall, independent of its brightness — a
 * multiplier on the halo's footprint. 1 = tied to Bloom/Glow as before; lower
 * pulls the glow into a tight aura at the seam, higher throws it far across
 * the wall.
 * @label Glow Spread
 * @default 1
 * @range 0.25, 2
 */
uniform float u_glowSpread;

// SECTION: Effects
/**
 * Brightness of the ball's glow on the wall, independent of its reach.
 * 1 = unchanged; use with Glow Spread to set reach and heat separately
 * (Bloom/Glow alone couples them).
 * @label Glow Intensity
 * @default 1
 * @range 0, 4
 */
uniform float u_glowIntensity;

// SECTION: Effects
/**
 * Progressiveness of the glow's falloff across its reach. Low = a hot seam
 * that drops off steeply into a long faint tail; high = an even, plateau-like
 * glow that stays strong across its full footprint before letting go. 0.5
 * is the classic dome falloff.
 * @label Glow Curve
 * @default 0.5
 * @range 0, 1
 */
uniform float u_glowCurve;

// SECTION: Effects
/**
 * Lets the ball cast glow into the DARK bands too. The halo is normally
 * multiplied by the stripe light, so the side facing a dark band gets no glow
 * at all — this floors that modulation. 0 = glow only where the stripes light
 * the ball (classic); 1 = a full omnidirectional aura regardless of the
 * stripes, as if the ball itself were the light source.
 * @label Glow Fill
 * @default 0
 * @range 0, 1
 */
uniform float u_glowFloor;

// SECTION: Effects
/**
 * Time-shifts the glow's response to the stripes, as a fraction of the loop —
 * the halo trails (positive) or leads (negative) the ball's own rim lighting,
 * like an afterglow with inertia. 0 = in lockstep with the rim.
 * @label Glow Delay
 * @default 0
 * @range -0.5, 0.5
 */
uniform float u_glowLag;

// SECTION: Effects
/**
 * Additive glow — a light-leak layer that STACKS on top of the corona + halo,
 * overdriving the hottest spots. Clamped by the Highlight Ceiling and shaded
 * through the one palette like every other tone, so however hard it is pushed
 * it can never blow past the Color group's caps.
 * @label Additive Glow
 * @default 0
 * @range 0, 2
 */
uniform float u_glowAdd;

// SECTION: Effects
/**
 * Diffused, scattered light that spreads the corona deeper across the front face
 * instead of hugging the edge.
 * @label Diffuse Scatter
 * @default 0.18
 * @range 0, 2
 */
uniform float u_scatter;

// SECTION: Effects
/**
 * Falloff shape of the Diffuse Scatter. Higher spreads the scattered light more
 * evenly (a softer, more linear falloff) across the ball; lower keeps it tight to
 * the rim.
 * @label Scatter Spread
 * @default 0.5
 * @range 0, 1
 */
uniform float u_scatterSpread;

// SECTION: Effects
/**
 * Brightness of the scattered light on the ball — boosts the diffuse scatter's
 * glow independent of its amount and spread. 1 = unchanged.
 * @label Scatter Intensity
 * @default 1
 * @range 0, 4
 */
uniform float u_scatterIntensity;

// SECTION: Effects
/**
 * Fresnel edge sharpness — a crisp bright line right at the silhouette on top of
 * the soft corona.
 * @label Fresnel Power
 * @default 0.4
 * @range 0, 2
 */
uniform float u_fresnel;

// SECTION: Effects
/**
 * Opposite of Fresnel — darkens the viewer-facing centre of the ball, setting how
 * much of the core stays black. Higher pushes the dark region further out toward
 * the rim (past 1 it starts dimming the rim too); 0 leaves only the natural falloff.
 * @label Dark Core
 * @default 0.35
 * @range 0, 2
 */
uniform float u_darkCore;

// SECTION: Effects
/**
 * Adds pure black into the dark core. The Dark Core alone bottoms out at the
 * palette's tinted near-black; push this up to crush the centre to true black.
 * @label Core Black
 * @default 0
 * @range 0, 1
 */
uniform float u_coreBlack;

// SECTION: Effects
/**
 * Ambient fill so the shadow side never drops fully to black.
 * @label Ambient
 * @default 0.18
 * @range 0, 1
 */
uniform float u_ambient;

// SECTION: Effects
/**
 * Depth blur — global depth-of-field: softens the wall light and extends how far
 * the bloom and cast shadow reach, all progressively with distance from the ball.
 * The seam stays crisp while everything recedes out of focus, selling the ball as
 * a hemisphere set into the wall.
 * @label Depth Blur
 * @default 0.5
 * @range 0, 1
 */
uniform float u_depthBlur;

// SECTION: Dark Glow
/**
 * The bright glow's dark twin: a lobe that follows the glow around the ball
 * on its own delayed clock and ABSORBS wall light instead of adding it — the
 * backdrop under it goes darker and more saturated, a dense wave trailing
 * the bright one. 0 = off.
 * @label Amount
 * @default 0
 * @range 0, 1
 */
uniform float u_dgAmount;

// SECTION: Dark Glow
/**
 * How hard the wave dims the wall beneath it — the raw absorption depth,
 * independent of Amount (which sets the wave's overall presence). Crank both
 * for a wave that swallows the backdrop almost to black.
 * @label Darkness
 * @default 0.7
 * @range 0, 1
 */
uniform float u_dgDarkness;

// SECTION: Dark Glow
/**
 * Reach of the dark glow across the wall — a tight dark aura at the seam vs
 * a deep wave rolling far from the ball.
 * @label Spread
 * @default 0.5
 * @range 0, 1
 */
uniform float u_dgSpread;

// SECTION: Dark Glow
/**
 * Progressiveness of the falloff, matching Glow Curve: low = dense at the
 * seam dropping into a long faint tail, high = an even shade across the full
 * footprint. 0.5 = the classic dome.
 * @label Curve
 * @default 0.5
 * @range 0, 1
 */
uniform float u_dgCurve;

// SECTION: Dark Glow
/**
 * How far behind the bright glow the dark one trails, as a fraction of the
 * loop. Positive = it chases the light (an after-wave); negative = it runs
 * ahead of it; 0 = right on top of the glow, cancelling it into a dim dense
 * aura.
 * @label Delay
 * @default 0.15
 * @range -0.5, 0.5
 */
uniform float u_dgDelay;

// SECTION: Dark Glow
/**
 * How much the absorbed light densifies in colour — the darkened wall is
 * pushed toward a deeper, juicier version of its own hue AND dyed with a
 * deep vivid key tone, which keeps the wave visible even over the dark
 * bands where pure dimming would vanish. 0 = the dark glow only dims.
 * @label Saturation
 * @default 0.7
 * @range 0, 1
 */
uniform float u_dgSat;

// SECTION: Drop Shadow
/**
 * The simplest reading of a shadow: a blurred disc sitting behind the ball,
 * darkening the wall beneath it. It sits BELOW the glow — the halo and
 * additive glow stack on top and shine over it, never shaded by it. 0 = off.
 * @label Opacity
 * @default 0
 * @range 0, 1
 */
uniform float u_dropAmount;

// SECTION: Drop Shadow
/**
 * Radius of the disc relative to the ball — 1 hides exactly behind the
 * silhouette, larger peeks out as a dark aura.
 * @label Size
 * @default 1.15
 * @range 0.4, 2
 */
uniform float u_dropSize;

// SECTION: Drop Shadow
/**
 * Edge blur of the disc — 0 is a hard-edged circle, 1 melts it into a soft
 * dark breath with no visible boundary.
 * @label Blur
 * @default 0.5
 * @range 0, 1
 */
uniform float u_dropBlur;

// SECTION: Drop Shadow
/**
 * Makes the blur progressive with distance from the ball: where the disc's
 * edge hugs the silhouette it stays crisp (a contact shadow), and it melts
 * more the farther it reaches — like a real shadow diffusing away from its
 * caster. 0 = uniform blur everywhere.
 * @label Blur Progression
 * @default 0.65
 * @range 0, 1
 */
uniform float u_dropBlurProg;

// SECTION: Drop Shadow
/**
 * Horizontal offset of the disc from the ball's centre, in ball radii —
 * slide it out to one side like a classic cast drop shadow.
 * @label Offset X
 * @default 0
 * @range -1, 1
 */
uniform float u_dropX;

// SECTION: Drop Shadow
/**
 * Vertical offset of the disc, in ball radii — negative drops it below the
 * ball.
 * @label Offset Y
 * @default 0
 * @range -1, 1
 */
uniform float u_dropY;

// SECTION: Drop Shadow
/**
 * Width of the shadow waves' travel. TWO discs ride the light grating in ONE
 * direction, half a period apart, with complementary fades that always sum
 * to one — each eases fully out before it wraps while its partner eases in
 * on the far side, so the shadow loops seamlessly: no pop, no gap, no
 * backswing, at any value. The first wave peaks as a dark band crosses the
 * ball. Offset X/Y set the home line. 0 = one static disc.
 * @label Sway
 * @default 0.5
 * @range 0, 1
 */
uniform float u_dropSway;

// SECTION: Drop Shadow
/**
 * Time-shifts the disc's sway off the backdrop clock, as a fraction of the
 * loop — positive trails the stripes like a shadow with inertia, negative
 * anticipates them.
 * @label Sway Delay
 * @default 0
 * @range -0.5, 0.5
 */
uniform float u_dropSwayLag;

// SECTION: Drop Shadow
/**
 * Fades the shadow with its distance from the ball — the farther a wave
 * carries the disc from its caster, the thinner its opacity, dissolving
 * toward the far end of the travel. 0 = full opacity everywhere.
 * @label Distance Fade
 * @default 0.5
 * @range 0, 1
 */
uniform float u_dropDistFade;

// SECTION: Drop Shadow
/**
 * Dyes the disc with the Key Color's hue instead of leaving it a plain
 * black layer — 0 = pure darkening, 1 = a fully key-saturated shade. A
 * neutral key stays neutral.
 * @label Saturation
 * @default 0.6
 * @range 0, 1
 */
uniform float u_dropSat;

// SECTION: Drop Shadow
/**
 * Brightness of the disc's key dye — low keeps it a deep inky tint, high
 * lifts it toward a luminous colored shade that visibly carries the hue
 * against the backdrop.
 * @label Tint Brightness
 * @default 0.35
 * @range 0, 1
 */
uniform float u_dropVal;

// SECTION: Drop Shadow
/**
 * Chromatic aberration of the shadow discs — each colour channel reads the
 * disc a hair to the side, so the blurred edge fringes into colour, matching
 * the stripe Dispersion's lens character. 0 = clean edge.
 * @label Dispersion
 * @default 0.4
 * @range 0, 1
 */
uniform float u_dropDisp;


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
// near-black shadow (still tinted by the key hue) through the key to a near-white
// highlight — so ball and wall share one family of hues, darks and brights.
vec3 palette(float t, vec3 keyLin) {
  t = clamp(t, 0.0, 1.2);
  vec3 shadow = keyLin * 0.02;
  vec3 mid = keyLin;
  // Highlight tops: blend between washing toward white (low saturation, bright
  // but grey-ish) and staying vividly in the key hue by scaling the colour up
  // (high saturation). Highlight Saturation picks the balance.
  vec3 hi = mix(mix(keyLin, vec3(1.0), 0.55), clamp(keyLin * 2.2, 0.0, 1.0), u_highlightSat);
  vec3 peak = mix(mix(keyLin, vec3(1.0), 0.9), clamp(keyLin * 3.2, 0.0, 1.0), u_highlightSat);
  if (t < 0.5) return mix(shadow, mid, smoothstep(0.0, 0.5, t));
  if (t < 1.0) return mix(mid, hi, smoothstep(0.5, 1.0, t));
  return mix(hi, peak, smoothstep(1.0, 1.2, t));
}

// Shade a per-channel illumination triple through the ONE palette. Each channel
// is a genuine palette sample, so the result can never leave the key family — the
// only way colours separate is Dispersion feeding slightly different levels per
// channel (a spatial offset upstream), which fringes blue↔white, never magenta.
vec3 shadeRGB(vec3 t, vec3 keyLin) {
  return vec3(
    palette(t.x, keyLin).r,
    palette(t.y, keyLin).g,
    palette(t.z, keyLin).b
  );
}

// The softbox as a tall vertical stripe of light at horizontal position `x`
// (in [-1,1] frame units). It's periodic with period P and scrolls left, so it
// travels right→left and wraps with NO pop — a seamless one-directional loop.
// Both the wall and the ball rim sample this ONE field, so they stay in sync.
float stripeField(float x, float scroll, float period, float soft, float balance) {
  // Regular grating: cos crosses zero at even spacing, so the bright and dark
  // bands are geometrically equal. `period` is one light+dark pair; `soft` morphs
  // a hard square (→0) to a smooth sine (→1). `balance` shifts the duty cycle
  // (threshold) to trim light vs dark width — used to make them read equal once
  // the palette/gamma tone curve is applied. Wall and ball rim share this field.
  float s = cos((x + scroll) / period * 6.2831853) - balance;
  return smoothstep(-soft, soft, s);
}

// Progressive blur: average the grating over a horizontal kernel whose radius is
// `spread`. Fed a spread that grows with distance from the ball, it stays sharp
// at the seam and softens into the distance — an AO/penumbra-like depth cue.
float blurStripe(float x, float scroll, float period, float soft, float balance, float spread) {
  const int TAPS = 5;
  float sum = 0.0;
  float wsum = 0.0;
  for (int i = 0; i < TAPS; i++) {
    float o = float(i) - 2.0;            // -2 .. 2
    float gw = exp(-o * o * 0.5);
    sum += stripeField(x + o * spread * 0.5, scroll, period, soft, balance) * gw;
    wsum += gw;
  }
  return sum / wsum;
}

// The sphere's scatter dome reflected across the silhouette onto the wall: crisp
// at the edge (r=1) and diffusing progressively softer to nothing at r=1+width —
// the mirror of the ball's inward Diffuse Scatter. Used for BOTH the bright
// glow and the Dark Glow, so each is least blurred at the seam, blurrier out.
// `expo` shapes the falloff: high hugs the seam and tails off fast, low spreads
// an even plateau across the full width.
float mirrorDome(float r, float width, float expo) {
  float d = clamp((r - 1.0) / max(width, 1.0e-3), 0.0, 1.0);
  float zMir = sqrt(max(1.0 - (1.0 - d) * (1.0 - d), 0.0));
  return pow(1.0 - zMir, expo) * step(1.0, r);
}

// A soft-edged disc: 1 inside, easing to 0 across the blur band. Used by the
// Drop Shadow, evaluated once per colour channel for its dispersion fringe.
float discMask(vec2 cRel, float radius, float blur) {
  float d = length(cRel) / radius;
  return 1.0 - smoothstep(1.0 - blur, 1.0 + 1.5 * blur, d);
}

// Soft highlight ceiling: near-linear below `ceil`, smoothly saturating toward it
// so no tone blows out to white. k=3 keeps mid-tones close to linear.
vec3 softClip(vec3 t, float ceil) {
  vec3 x = t / ceil;
  return ceil * x / pow(1.0 + x * x * x, vec3(1.0 / 3.0));
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;

  // Centered, aspect-corrected coords: 1 unit == viewport half-height.
  vec2 p = uv - 0.5;
  p.x *= aspect;
  // Horizontal coord that spans exactly [-1, 1] across the width, aspect-free.
  float nx = 2.0 * uv.x - 1.0;

  // Ball placement. Depth scales apparent radius (closer == bigger).
  vec2 c = p - vec2(u_ballX, u_ballY) * 0.5;
  float depthScale = 1.0 / clamp(1.0 - 0.4 * u_ballZ, 0.3, 2.0);
  float R = u_ballSize * depthScale;
  float r = length(c) / R;

  // Fake surface normal from the projected circle (only meaningful for r <= 1).
  float z = sqrt(max(1.0 - r * r, 0.0));
  vec2 outward = normalize(c + vec2(1.0e-5));

  // --- The travelling light grating (single source of light) ---
  // Regular equal-width light/dark stripes. Stripe Width sets the band width
  // (period = 2 × width); Stripe Softness morphs a sharp square ↔ a smooth sine.
  // The grating scrolls right→left and loops seamlessly, and the wall, rim and
  // both shadows all sample this ONE field so they move together.
  float bandW = max(u_density, 0.03);            // width of one light (or dark) band
  float period = 2.0 * bandW;
  float scroll = fract(u_time / max(u_loopDur, 0.1)) * period;
  // The ball's light/shadows can lead or lag the wall stripes by a phase offset
  // (in periods) — so the light reaches the ball sooner or later than the tiles.
  float ballScroll = scroll + u_lightLag * period;
  float soft = mix(0.05, 1.0, clamp(u_sweepFalloff, 0.0, 1.0));

  // Dispersion = a small per-channel SPATIAL offset of where each colour samples
  // the stripe. R/G/B thus read genuine palette colours a hair apart → a blue↔
  // white lens fringe, never an invented hue. disp = 0 collapses to one sample.
  float disp = u_dispersion * 0.05;
  vec3 chOff = vec3(-disp, 0.0, disp);

  // Wall samples the stripe at its own x; each ball-rim point samples Light
  // Reach further out along its own normal, so a rim point "sees" the stripe it
  // faces — the lever that makes the corona lobe sweep around the silhouette.
  // Both share the one field, so wall and ball move together.
  float bx = nx + u_rimReach * outward.x;
  // Depth blur radius grows with distance outside the ball → crisp seam, soft
  // distance. The ball rim (r≈1) gets ~0 spread, so it stays sharp.
  float spread = u_depthBlur * max(r - 1.0, 0.0) * 0.6;
  vec3 sBg = vec3(
    blurStripe(nx + chOff.x, scroll, period, soft, u_stripeBalance, spread),
    blurStripe(nx + chOff.y, scroll, period, soft, u_stripeBalance, spread),
    blurStripe(nx + chOff.z, scroll, period, soft, u_stripeBalance, spread)
  );
  vec3 sBall = vec3(
    stripeField(bx + chOff.x, ballScroll, period, soft, u_stripeBalance),
    stripeField(bx + chOff.y, ballScroll, period, soft, u_stripeBalance),
    stripeField(bx + chOff.z, ballScroll, period, soft, u_stripeBalance)
  );
  // Light Tracking: turn the rim's read of the grating from a gentle modulation
  // into a hard follow. Sharpening the stripe response concentrates the glow
  // into a lobe facing the light band; cutting the ambient floor lets the
  // dark-band side fall to near-black; the final gain overheats the lit lobe so
  // it blooms (softClip catches it) instead of merely staying on.
  float trk = clamp(u_rimFollow, 0.0, 1.0);
  vec3 sTrk = mix(sBall, smoothstep(vec3(0.15), vec3(0.85), sBall), trk);
  float ambFloor = u_ambient * (1.0 - 0.85 * trk);
  vec3 ballLit = ambFloor + (1.0 - ambFloor) * sTrk;
  ballLit *= 1.0 + trk * sTrk;

  // --- Fresnel terms (per-fragment, shared by all channels) ---
  float pEff = mix(10.0, 1.5, clamp(u_coronaWidth, 0.0, 1.0));
  // Radial basis for the corona: (1 - z) hugs the edge (sphere curvature), r is
  // linear in radius. Corona Linearity blends between them to spread the gradient.
  float rimCoord = mix(1.0 - z, r, clamp(u_rimLinear, 0.0, 1.0));
  float rimF = pow(rimCoord, pEff);  // main corona band
  float edge = pow(1.0 - z, 16.0);   // crisp Fresnel edge line (kept at the true edge)
  float scatExp = mix(3.5, 0.5, u_scatterSpread); // lower exponent → more linear falloff
  float scat = pow(rimCoord, scatExp); // scattered fill toward the center
  float rimBase = rimF + u_fresnel * edge + u_scatter * u_scatterIntensity * scat;

  // --- Backdrop illumination level: dark base + the bright travelling stripe ---
  float vig = smoothstep(1.7, 0.2, length(p));
  // Stripe endpoints: the grating interpolates from the dark level (trough) to
  // the light level (peak), each set independently.
  float darkLevel = mix(0.0, 0.28, u_wallBright);   // how dark the dark bands are (0 = black)
  float lightLevel = mix(0.1, 1.6, u_stripeLight);  // how bright/white the light bands are
  float bgMul = (1.0 + 0.3 * u_backdropZ) * mix(1.0, 0.65 + 0.35 * vig, 0.4);
  vec3 tBg = mix(vec3(darkLevel), vec3(lightLevel), sBg) * bgMul;

  // --- Ball illumination level (rim only; center → 0 → shadow color) ---
  vec3 tBall = (rimBase * ballLit + u_emissive * rimF) * u_coronaIntensity;
  // Opposite fresnel: carve a dark core out of the viewer-facing centre (high z).
  float coreMask = smoothstep(1.0 - u_darkCore, 1.0, z); // 1 at centre → 0 at rim
  tBall *= 1.0 - coreMask;

  // --- Bloom / Glow: the Diffuse Scatter mirrored across the silhouette ---
  // Inside the ball the scatter is pow(1 - z, 2), crisp at the rim and fading
  // toward the center. Reflect that dome onto the wall: it starts crisp at the
  // edge (the reflected silhouette has a hard edge) and grows progressively
  // softer/more diffuse outward — so the glow is least blurred nearest the ball
  // and blurrier the farther it reaches. Bloom sets the reach: a small glow stays
  // tight (little blur), a large one diffuses far (more blur).
  float atmos = mix(0.7, 1.5, u_depthBlur);   // Depth Blur scales how far glow/dark-glow reach
  float glowW = (0.25 + 1.5 * u_bloom) * atmos * u_glowSpread;
  float glow = mirrorDome(r, glowW, mix(3.5, 0.5, u_glowCurve));
  // The halo reads the grating on its OWN clock (Glow Delay shifts it off the
  // ball's rim lighting), through the same tracking transform as the rim so
  // both respond to the stripes with the same contrast. Glow Fill then floors
  // the modulation, letting the ball throw light into the dark bands too.
  float glowScroll = ballScroll + u_glowLag * period;
  vec3 sGlow = vec3(
    stripeField(bx + chOff.x, glowScroll, period, soft, u_stripeBalance),
    stripeField(bx + chOff.y, glowScroll, period, soft, u_stripeBalance),
    stripeField(bx + chOff.z, glowScroll, period, soft, u_stripeBalance)
  );
  vec3 sGlowTrk = mix(sGlow, smoothstep(vec3(0.15), vec3(0.85), sGlow), trk);
  vec3 glowLit = ambFloor + (1.0 - ambFloor) * sGlowTrk;
  glowLit *= 1.0 + trk * sGlowTrk;
  glowLit = max(glowLit, vec3(u_glowFloor));
  vec3 halo = glow * glowLit * (u_bloom * 1.3 + 0.5 * u_emissive) * u_glowIntensity;
  // Drop Shadow (below the glow): the disc darkens the wall BEFORE the halo
  // stacks on, so the glow shines over the shadow instead of being shaded by
  // it. Sway throws the disc away from the sweeping light on its own delayed
  // clock around the static offsets; the blur grades from crisp at the
  // ball's seam to melted far away. The key dye follows in the colour stage.
  float dsScroll = scroll + u_dropSwayLag * period;
  float dsNx = u_ballX / aspect;
  // One-way waves, TWIN discs: both ride the grating's phase right→left with
  // the stripes, half a period apart. Their envelopes are exact complements
  // (sin² + cos² = 1): each disc eases C¹-smoothly to ZERO before its
  // position wraps (so the jump is always fully hidden — no pop at any Sway
  // value), one is always fading in while the other fades out, and the two
  // weights sum to one so total shadow presence never dips or doubles. At
  // Sway 0 the discs coincide and the pair collapses to one steady disc.
  // The first wave peaks as a DARK band crosses the ball.
  float dsPh = fract((dsNx + dsScroll) / period);
  float dsPh2 = fract(dsPh + 0.5);
  float dropAway = clamp((r - 1.0) / 1.2, 0.0, 1.0);
  float dropGrade = mix(1.0, mix(0.12, 1.8, dropAway), u_dropBlurProg);
  float dropB = max(u_dropBlur * dropGrade, 0.01);
  float dsE1 = sin(3.14159265 * dsPh);
  dsE1 *= dsE1;
  float dsE2 = 1.0 - dsE1;
  // Distance Fade: each wave thins as its disc travels away from the ball —
  // a shadow dissolving as it leaves its caster.
  vec2 dropOff1 = vec2(u_dropX + u_dropSway * (0.5 - dsPh) * 2.4, u_dropY);
  vec2 dropOff2 = vec2(u_dropX + u_dropSway * (0.5 - dsPh2) * 2.4, u_dropY);
  float dropW1 = dsE1 * exp(-dot(dropOff1, dropOff1) * u_dropDistFade * 1.5);
  float dropW2 = dsE2 * exp(-dot(dropOff2, dropOff2) * u_dropDistFade * 1.5);
  // Dispersion: each colour channel reads the discs a hair to the side, so
  // the blurred edges fringe into colour through the palette.
  float dsD = u_dropDisp * 0.1 * R;
  vec2 dropC1 = c - dropOff1 * R;
  vec2 dropC2 = c - dropOff2 * R;
  float dropSizeR = max(R * u_dropSize, 1.0e-4);
  vec3 dropM1 = vec3(
    discMask(dropC1 - vec2(dsD, 0.0), dropSizeR, dropB),
    discMask(dropC1, dropSizeR, dropB),
    discMask(dropC1 + vec2(dsD, 0.0), dropSizeR, dropB));
  vec3 dropM2 = vec3(
    discMask(dropC2 - vec2(dsD, 0.0), dropSizeR, dropB),
    discMask(dropC2, dropSizeR, dropB),
    discMask(dropC2 + vec2(dsD, 0.0), dropSizeR, dropB));
  vec3 dropMask = (dropM1 * dropW1 + dropM2 * dropW2) * u_dropAmount;
  tBg *= 1.0 - dropMask;
  tBg += halo;
  // Capture the corona/halo brightness as the additive glow's source — it is
  // stacked back into the illumination just before the ceiling below.
  float glowIn = dot(tBall, vec3(0.3333));
  float glowOut = dot(halo, vec3(0.3333));

  // --- Dark Glow footprint: the bright glow's dark twin, trailing it ---
  // Same dome mechanics and stripe tracking as the glow, on a clock offset
  // from the GLOW's (Delay), so the dark wave chases the bright one. Only the
  // footprint is computed here; the colour stage darkens + densifies.
  float dgDome = mirrorDome(r, (0.1 + 1.4 * u_dgSpread) * atmos, mix(3.5, 0.5, u_dgCurve));
  float dgScroll = glowScroll + u_dgDelay * period;
  float sDark = stripeField(bx, dgScroll, period, soft, u_stripeBalance);
  float sDarkTrk = mix(sDark, smoothstep(0.15, 0.85, sDark), trk);
  float dgLit = ambFloor + (1.0 - ambFloor) * sDarkTrk;
  float dark = clamp(dgDome * dgLit * u_dgAmount * 1.6, 0.0, 1.0);

  // Additive glow: stack the light-leak in ILLUMINATION space, before the
  // ceiling — it overdrives the hottest spots like a real leak, but the same
  // Highlight Ceiling clamps it and the same palette shades it (Highlight
  // Saturation, hue drifts), so the Color group always has the last word.
  tBall += vec3(glowIn * u_glowAdd);
  tBg += vec3(glowOut * u_glowAdd);

  // Highlight ceiling: soft-limit every tone so nothing blows out to white.
  float tCeil = mix(0.6, 1.2, u_highlightCap);
  tBg = softClip(tBg, tCeil);
  tBall = softClip(tBall, tCeil);

  // --- Shade both through the ONE palette ---
  vec3 keyLin = toLinear(u_key);
  vec3 bgCol = shadeRGB(tBg, keyLin);
  // Dark Glow colour treatment, three passes: absorb (Darkness dims the wall
  // under the wave), densify what remains away from its own grey, then dye
  // toward a deep vivid key tone — the dye is what keeps the wave visible
  // even over the already-dark bands, where pure dimming would vanish.
  // Darker AND more saturated everywhere, never grey, never lost.
  bgCol *= 1.0 - 0.95 * u_dgDarkness * dark;
  float dgLuma = dot(bgCol, vec3(0.2126, 0.7152, 0.0722));
  vec3 dgDense = max(mix(vec3(dgLuma), bgCol, 1.0 + 1.5 * u_dgSat), 0.0);
  bgCol = mix(bgCol, dgDense, dark);
  vec3 dgKeyHsv = rgb2hsv(u_key);
  vec3 dgDye = toLinear(hsv2rgb(vec3(dgKeyHsv.x, sqrt(dgKeyHsv.y), 0.32)));
  bgCol = mix(bgCol, dgDye, dark * u_dgSat * 0.55);
  // Drop Shadow dye (below the glow): tint the shadowed disc toward the key
  // shade, fading out where the halo is strong so the glow reads on top of
  // the shadow, never under it. The darkening itself already happened in
  // illumination space, before the halo was stacked.
  vec3 dropDye = toLinear(hsv2rgb(vec3(dgKeyHsv.x, sqrt(dgKeyHsv.y), mix(0.08, 0.7, u_dropVal))));
  bgCol = mix(bgCol, dropDye, dropMask * u_dropSat * exp(-glowOut * 3.0));
  vec3 ballCol = shadeRGB(tBall, keyLin);
  // Core Black: crush the core toward true black, past the palette's tinted floor.
  ballCol *= 1.0 - u_coreBlack * coreMask;

  float px = 1.0 / (R * u_resolution.y);
  float ballMask = smoothstep(1.0 + 1.5 * px, 1.0 - 1.5 * px, r);
  vec3 col = mix(bgCol, ballCol, ballMask);

  // Hue Lit / Hue Shadow: signed analogous drift at each end of the light
  // gradient (Tube's model). `lit` is the pixel's actual illumination level —
  // not the raw stripe phase — so the black core stays put while the corona
  // lobe and bright bands drift. Applied to ball and wall alike so they stay
  // hue-matched.
  float lit = mix(tBg.y, tBall.y, ballMask);
  float litN = smoothstep(0.35, 0.85, lit);
  float darkN = smoothstep(0.35, 0.05, lit);
  vec3 hsv = rgb2hsv(col);
  hsv.x = fract(hsv.x + 0.06 * (u_hueSpread * litN + u_hueShadow * darkN) + 1.0);
  col = hsv2rgb(hsv);

  // Gamma-encode (toGamma clamps to [0,1], so hue/dispersion can't push a
  // channel past white on screen).
  col = toGamma(col);

  // Dither to kill gradient banding on the wall.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
