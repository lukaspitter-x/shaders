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
 * How sharply the softbox gradient falls off across the frame — low is a broad,
 * gentle wash; high concentrates the light into a narrower travelling band.
 * @label Sweep Falloff
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
 * Fake bloom: soft halo bleeding outside the silhouette onto the wall, plus a
 * white blow-out at the brightest part of the rim.
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
 * Contact / ambient shadow: darkening of the wall hugging the ball, where the
 * ball occludes ambient light.
 * @label Contact Shadow
 * @default 0.5
 * @range 0, 1
 */
uniform float u_contact;

// SECTION: Effects
/**
 * Ambient fill so the shadow side never drops fully to black.
 * @label Ambient
 * @default 0.18
 * @range 0, 1
 */
uniform float u_ambient;

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
  vec3 hi = mix(keyLin, vec3(1.0), 0.9);
  if (t < 0.5) return mix(shadow, mid, smoothstep(0.0, 0.5, t));
  return mix(mid, hi, smoothstep(0.5, 1.0, t));
}

// Dispersion: sample the ramp at slightly offset levels per channel, so steep
// light transitions fringe warm (R leads) → cool (B lags) like lens dispersion.
vec3 shade(float t, vec3 keyLin) {
  float d = u_dispersion * 0.18;
  return vec3(
    palette(t + d, keyLin).r,
    palette(t, keyLin).g,
    palette(t - d, keyLin).b
  );
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

  // --- The softbox: one horizontal light term drives both surfaces ---
  // Lx = +1 light from the right, -1 from the left. cos() sweeps right→left→front
  // and loops seamlessly. Everything downstream reads from this one value, so the
  // wall gradient and the ball highlight always move together.
  float phase = fract(u_time / max(u_loopDur, 0.1));
  float Lx = cos(phase * 6.2831853);

  // Signed alignment of a point with the light (-1 shadow side .. +1 lit side).
  float bgAlign = clamp(nx, -1.0, 1.0) * Lx;
  float ballAlign = clamp(outward.x, -1.0, 1.0) * Lx;

  // Softbox falloff shapes how the lit→shadow gradient ramps across the frame.
  float bgLit = pow(clamp(0.5 + 0.5 * bgAlign, 0.0, 1.0), u_sweepFalloff);
  float ballLit = u_ambient + (1.0 - u_ambient) *
      pow(clamp(0.5 + 0.5 * ballAlign, 0.0, 1.0), u_sweepFalloff);

  // --- Backdrop illumination level ---
  float vig = smoothstep(1.7, 0.2, length(p));
  float tBg = u_wallBright * (0.35 + 0.85 * bgLit);
  tBg *= 1.0 + 0.3 * u_backdropZ;
  tBg *= mix(1.0, 0.65 + 0.35 * vig, 0.5);

  // --- Ball illumination level (rim only; center → 0 → shadow color) ---
  float pEff = mix(10.0, 1.5, clamp(u_coronaWidth, 0.0, 1.0));
  float rimF = pow(1.0 - z, pEff);   // main corona band
  float edge = pow(1.0 - z, 16.0);   // crisp Fresnel edge line
  float scat = pow(1.0 - z, 2.0);    // scattered fill toward the center
  float rimIllum = (rimF + u_fresnel * edge + u_scatter * scat) * ballLit;
  rimIllum += u_emissive * rimF;     // self-lit: independent of direction
  rimIllum *= u_coronaIntensity;
  float tBall = rimIllum;

  // --- Emissive + bloom spill from the ball onto the wall (in sync via ballLit) ---
  float outer = smoothstep(1.0 + (0.12 + 0.55 * u_bloom), 1.0, r);
  float halo = outer * outer * ballLit * (u_bloom + 0.5 * u_emissive);
  tBg += halo;

  // Contact / ambient shadow: the ball occludes ambient light on the near wall.
  float contact = 1.0 - smoothstep(1.0, 1.18, r);
  tBg -= u_contact * contact * 0.6;
  tBg = max(tBg, 0.0);

  // --- Shade both through the ONE palette (with dispersion) ---
  vec3 keyLin = toLinear(u_key);
  vec3 bgCol = shade(tBg, keyLin);
  vec3 ballCol = shade(tBall, keyLin);

  float px = 1.0 / (R * u_resolution.y);
  float ballMask = smoothstep(1.0 + 1.5 * px, 1.0 - 1.5 * px, r);
  vec3 col = mix(bgCol, ballCol, ballMask);

  // Bloom blow-out: extra white where the rim goes super-bright.
  vec3 hiWhite = mix(keyLin, vec3(1.0), 0.9);
  col += hiWhite * pow(max(rimIllum - 1.0, 0.0), 1.5) * u_bloom * 0.4 * ballMask;

  // Hue Spread: analogous drift, warmer toward the softbox — applied uniformly to
  // ball and wall so they stay hue-matched.
  float alignFinal = mix(bgAlign, ballAlign, ballMask);
  vec3 hsv = rgb2hsv(col);
  hsv.x = fract(hsv.x + u_hueSpread * 0.04 * alignFinal);
  col = hsv2rgb(hsv);

  // Soft filmic clamp keeps highlights from clipping while blacks stay black.
  col = col / (1.0 + col);
  col = toGamma(col);

  // Dither to kill gradient banding on the wall.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
