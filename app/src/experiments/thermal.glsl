/**
 * Thermal — a dark ball against a backdrop wall, lit by a tall softbox that
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
 * Analogous hue drift across the light gradient (warmer toward the softbox,
 * cooler away). 0 = strict monochrome; higher = juicier.
 * @label Hue Spread
 * @default 0.25
 * @range 0, 1
 */
uniform float u_hueSpread;

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
 * Base brightness of the backdrop wall.
 * @label Wall Brightness
 * @default 0.5
 * @range 0, 1
 */
uniform float u_wallBright;

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
 * Width of the travelling light stripe — low is a broad, soft wash across the
 * wall; high concentrates it into a narrow, defined band.
 * @label Stripe Width
 * @default 1
 * @range 0.2, 4
 */
uniform float u_sweepFalloff;

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
 * glow that reaches farther and blurs more toward its outer edge.
 * @label Bloom / Glow
 * @default 0.8
 * @range 0, 2
 */
uniform float u_bloom;

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
 * Fresnel edge sharpness — a crisp bright line right at the silhouette on top of
 * the soft corona.
 * @label Fresnel Power
 * @default 0.4
 * @range 0, 2
 */
uniform float u_fresnel;

// SECTION: Effects
/**
 * Strength of the shadow the ball casts on the wall — a directional lobe thrown
 * away from the lit side, plus a faint seam AO. Softness with distance is set by
 * Depth Blur.
 * @label Cast Shadow
 * @default 0.5
 * @range 0, 1
 */
uniform float u_contact;

// SECTION: Effects
/**
 * Flip the cast shadow to the opposite side of the ball — toward the softbox
 * instead of away from it.
 * @label Flip Shadow
 * @switch
 * @default 0
 */
uniform float u_flipShadow;

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
  // Brighten toward the key's own hue first, only tipping to near-white at the
  // very top — so wall highlights stay a saturated light-blue, not grey.
  vec3 hi = mix(keyLin, vec3(1.0), 0.55);
  vec3 peak = mix(keyLin, vec3(1.0), 0.9);
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
float stripeField(float x, float scroll, float w, float P) {
  float d = x + scroll;
  d = d - P * floor(d / P + 0.5);   // nearest copy, wrapped to [-P/2, P/2]
  return exp(-(d * d) / (w * w));
}

// Progressive blur: average the stripe over a horizontal kernel whose radius is
// `spread`. Fed a spread that grows with distance from the ball, it stays sharp
// at the seam and softens into the distance — an AO/penumbra-like depth cue.
float blurStripe(float x, float scroll, float w, float P, float spread) {
  const int TAPS = 5;
  float sum = 0.0;
  float wsum = 0.0;
  for (int i = 0; i < TAPS; i++) {
    float o = float(i) - 2.0;            // -2 .. 2
    float gw = exp(-o * o * 0.5);
    sum += stripeField(x + o * spread * 0.5, scroll, w, P) * gw;
    wsum += gw;
  }
  return sum / wsum;
}

// The sphere's scatter dome reflected across the silhouette onto the wall: crisp
// at the edge (r=1) and diffusing progressively softer to nothing at r=1+width —
// the mirror of the ball's inward Diffuse Scatter. Used for BOTH the outward
// bloom and the cast shadow, so each is least blurred at the seam, blurrier out.
float mirrorDome(float r, float width) {
  float d = clamp((r - 1.0) / max(width, 1.0e-3), 0.0, 1.0);
  float zMir = sqrt(max(1.0 - (1.0 - d) * (1.0 - d), 0.0));
  return pow(1.0 - zMir, 2.0) * step(1.0, r);
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

  // --- The travelling softbox stripe (single source of light) ---
  const float P = 4.0;                                  // travel period
  float scroll = fract(u_time / max(u_loopDur, 0.1)) * P;
  float stripeW = mix(1.3, 0.3, clamp((u_sweepFalloff - 0.2) / 3.8, 0.0, 1.0));

  // Dispersion = a small per-channel SPATIAL offset of where each colour samples
  // the stripe. R/G/B thus read genuine palette colours a hair apart → a blue↔
  // white lens fringe, never an invented hue. disp = 0 collapses to one sample.
  float disp = u_dispersion * 0.05;
  vec3 chOff = vec3(-disp, 0.0, disp);

  // Wall samples the stripe at its own x; ball rim samples a touch further out
  // along the normal, so the lit side follows where the stripe faces. Both share
  // the one field, so wall and ball move together.
  float bx = nx + 0.25 * outward.x;
  // Depth blur radius grows with distance outside the ball → crisp seam, soft
  // distance. The ball rim (r≈1) gets ~0 spread, so it stays sharp.
  float spread = u_depthBlur * max(r - 1.0, 0.0) * 0.6;
  vec3 sBg = vec3(
    blurStripe(nx + chOff.x, scroll, stripeW, P, spread),
    blurStripe(nx + chOff.y, scroll, stripeW, P, spread),
    blurStripe(nx + chOff.z, scroll, stripeW, P, spread)
  );
  vec3 sBall = vec3(
    stripeField(bx + chOff.x, scroll, stripeW, P),
    stripeField(bx + chOff.y, scroll, stripeW, P),
    stripeField(bx + chOff.z, scroll, stripeW, P)
  );
  vec3 ballLit = u_ambient + (1.0 - u_ambient) * sBall;

  // --- Fresnel terms (per-fragment, shared by all channels) ---
  float pEff = mix(10.0, 1.5, clamp(u_coronaWidth, 0.0, 1.0));
  float rimF = pow(1.0 - z, pEff);   // main corona band
  float edge = pow(1.0 - z, 16.0);   // crisp Fresnel edge line
  float scat = pow(1.0 - z, 2.0);    // scattered fill toward the center
  float rimBase = rimF + u_fresnel * edge + u_scatter * scat;

  // --- Backdrop illumination level: dark base + the bright travelling stripe ---
  float vig = smoothstep(1.7, 0.2, length(p));
  float bgBase = mix(0.10, 0.28, u_wallBright);
  float bgGain = mix(0.45, 0.95, u_wallBright);
  float bgMul = (1.0 + 0.3 * u_backdropZ) * mix(1.0, 0.65 + 0.35 * vig, 0.4);
  vec3 tBg = (bgBase + sBg * bgGain) * bgMul;

  // --- Ball illumination level (rim only; center → 0 → shadow color) ---
  vec3 tBall = (rimBase * ballLit + u_emissive * rimF) * u_coronaIntensity;

  // --- Bloom / Glow: the Diffuse Scatter mirrored across the silhouette ---
  // Inside the ball the scatter is pow(1 - z, 2), crisp at the rim and fading
  // toward the center. Reflect that dome onto the wall: it starts crisp at the
  // edge (the reflected silhouette has a hard edge) and grows progressively
  // softer/more diffuse outward — so the glow is least blurred nearest the ball
  // and blurrier the farther it reaches. Bloom sets the reach: a small glow stays
  // tight (little blur), a large one diffuses far (more blur).
  float atmos = mix(0.7, 1.5, u_depthBlur);   // Depth Blur scales how far glow/shadow reach
  float glow = mirrorDome(r, (0.25 + 1.5 * u_bloom) * atmos);
  vec3 halo = glow * ballLit * (u_bloom * 1.3 + 0.5 * u_emissive);
  tBg += halo;

  // --- Cast shadow on the wall (the shadow half of the pair) ---
  // The ball blocks the softbox, darkening the wall AWAY from the lit side. Find
  // the light's horizontal direction from the stripe gradient at the ball, then
  // darken the wall where it faces away from the light, fading out from the seam.
  // Depth Blur sets how far and how softly the shadow reaches — crisp and tight
  // at low blur, long and diffuse at high blur (an area-light penumbra).
  float ballCenterNx = u_ballX / aspect;
  float sLeft = stripeField(ballCenterNx - 0.6, scroll, stripeW, P);
  float sRight = stripeField(ballCenterNx + 0.6, scroll, stripeW, P);
  vec2 Lv = normalize(vec2(sRight - sLeft, 0.0) + vec2(1.0e-4, 0.0));
  float sideAmt = clamp(abs(sRight - sLeft) * 3.0, 0.0, 1.0); // 0 when light is head-on
  // Same mirrored-dome profile as the bloom, but subtracting light on the side
  // away from the softbox — crisp at the seam, diffusing progressively outward.
  float sgn = mix(1.0, -1.0, u_flipShadow);                        // flip → shadow toward light
  float antiLight = clamp(dot(outward, -Lv) * sgn * 0.5 + 0.5, 0.0, 1.0); // 1 shadow side .. 0 other
  float shadowDome = mirrorDome(r, (0.25 + 1.5 * u_contact) * atmos);
  float castShadow = shadowDome * mix(0.2, 1.0, antiLight * sideAmt);
  tBg = max(tBg * (1.0 - clamp(u_contact * castShadow * 1.7, 0.0, 0.93)), 0.0);

  // Highlight ceiling: soft-limit every tone so nothing blows out to white.
  float tCeil = mix(0.6, 1.2, u_highlightCap);
  tBg = softClip(tBg, tCeil);
  tBall = softClip(tBall, tCeil);

  // --- Shade both through the ONE palette ---
  vec3 keyLin = toLinear(u_key);
  vec3 bgCol = shadeRGB(tBg, keyLin);
  vec3 ballCol = shadeRGB(tBall, keyLin);

  float px = 1.0 / (R * u_resolution.y);
  float ballMask = smoothstep(1.0 + 1.5 * px, 1.0 - 1.5 * px, r);
  vec3 col = mix(bgCol, ballCol, ballMask);

  // Hue Spread: subtle analogous drift, warmer toward the stripe — applied
  // uniformly to ball and wall so they stay hue-matched.
  float lit = mix(sBg.y, sBall.y, ballMask);
  vec3 hsv = rgb2hsv(col);
  hsv.x = fract(hsv.x + u_hueSpread * 0.03 * (lit - 0.5));
  col = hsv2rgb(hsv);

  // Highlights are already governed by the ceiling above; just gamma-encode
  // (toGamma clamps to [0,1], so hue/dispersion can't push a channel past white).
  col = toGamma(col);

  // Dither to kill gradient banding on the wall.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
