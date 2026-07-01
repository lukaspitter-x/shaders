/**
 * Thermal — a dark hemisphere embedded in a backdrop wall, backlit so light
 * escapes around the silhouette as a glowing corona. The front face stays dark
 * (an eclipse); the rim carries all the light. A single azimuth light orbits
 * behind the wall so the bright arc chases around the rim and loops seamlessly.
 *
 * Technique: 2.5D analytic sphere. For a pixel at normalized radius r in the
 * ball's projected circle, z = sqrt(1 - r^2) reconstructs a fake surface normal
 * without raymarching (Pencil-safe, cheap). Fresnel on that normal *is* the
 * corona: z is high on the front (dark) and → 0 at the silhouette (bright rim).
 *
 * One Key Color drives the whole palette: a deep desaturated sibling for the
 * wall, the key itself through the mid rim, and a near-white blow-out at the
 * hotspot — with a Hue Spread dial for analogous juice (0 = monochrome).
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * The one hue everything is derived from — wall, mid rim, and hotspot are all
 * ramped brightness/temperature siblings of this.
 * @section Color
 * @label Key Color
 * @color
 * @default #1f6bff
 */
uniform vec3 u_key;

/**
 * Analogous hue drift across the gradient (warmer toward the light, cooler
 * away). 0 = strict monochrome like the reference; higher = juicier.
 * @section Color
 * @label Hue Spread
 * @default 0.25
 * @range 0, 1
 */
uniform float u_hueSpread;

/**
 * Radius of the ball as a fraction of viewport half-height.
 * @section Ball
 * @label Size
 * @default 0.46
 * @range 0.1, 0.95
 */
uniform float u_ballSize;

/**
 * Horizontal position of the ball center.
 * @section Ball
 * @label Pos X
 * @default 0
 * @range -1, 1
 */
uniform float u_ballX;

/**
 * Vertical position of the ball center.
 * @section Ball
 * @label Pos Y
 * @default 0
 * @range -1, 1
 */
uniform float u_ballY;

/**
 * Depth toward/away from the viewer. Positive pushes the ball closer (larger,
 * softer corona); negative sinks it back.
 * @section Ball
 * @label Depth Z
 * @default 0
 * @range -1, 1
 */
uniform float u_ballZ;

/**
 * Base brightness of the backdrop wall.
 * @section Backdrop
 * @label Wall Brightness
 * @default 0.5
 * @range 0, 1
 */
uniform float u_wallBright;

/**
 * Move the wall on its Z axis — forward brightens and flattens it, back darkens
 * and deepens the vignette.
 * @section Backdrop
 * @label Backdrop Z
 * @default 0
 * @range -1, 1
 */
uniform float u_backdropZ;

/**
 * Seconds for the light to travel once fully around the rim. The loop is
 * seamless at any value.
 * @section Light
 * @label Loop Duration
 * @default 12
 * @range 2, 30
 */
uniform float u_loopDur;

/**
 * How far inward from the silhouette the light waves reach — thin ring vs broad
 * glow bleeding toward the center.
 * @section Light
 * @label Corona Width
 * @default 0.5
 * @range 0, 1
 */
uniform float u_coronaWidth;

/**
 * Master brightness of the corona.
 * @section Light
 * @label Corona Intensity
 * @default 1.6
 * @range 0, 4
 */
uniform float u_coronaIntensity;

/**
 * Fake emissive material: a self-lit glow on the rim that stays bright even on
 * the side facing away from the light.
 * @section Effects
 * @label Emissive
 * @default 0.35
 * @range 0, 2
 */
uniform float u_emissive;

/**
 * Fake bloom: soft halo bleeding outside the silhouette into the wall, plus a
 * white blow-out at the brightest part of the rim.
 * @section Effects
 * @label Bloom / Glow
 * @default 0.8
 * @range 0, 2
 */
uniform float u_bloom;

/**
 * Diffused, scattered light that spreads the corona deep across the front face
 * instead of hugging the edge.
 * @section Effects
 * @label Diffuse Scatter
 * @default 0.18
 * @range 0, 2
 */
uniform float u_scatter;

/**
 * Fresnel edge sharpness — a crisp bright line right at the silhouette on top of
 * the soft corona.
 * @section Effects
 * @label Fresnel Power
 * @default 0.4
 * @range 0, 2
 */
uniform float u_fresnel;

/**
 * Contact / ambient shadow: darkening of the wall hugging the ball, where the
 * ball occludes ambient light.
 * @section Effects
 * @label Contact Shadow
 * @default 0.5
 * @range 0, 1
 */
uniform float u_contact;

/**
 * Ambient fill so the dark side of the rim never drops fully to black.
 * @section Effects
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

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;

  // Centered, aspect-corrected coords: 1 unit == viewport half-height.
  vec2 p = uv - 0.5;
  p.x *= aspect;

  // Ball placement. Depth scales apparent radius (closer == bigger).
  vec2 c = p - vec2(u_ballX, u_ballY) * 0.5;
  float depthScale = 1.0 / clamp(1.0 - 0.4 * u_ballZ, 0.3, 2.0);
  float R = u_ballSize * depthScale;
  float r = length(c) / R;

  // Fake surface normal from the projected circle (only meaningful for r <= 1).
  float z = sqrt(max(1.0 - r * r, 0.0));
  vec2 outward = normalize(c + vec2(1.0e-5));

  // Azimuth light orbiting behind the wall — periodic, so it loops seamlessly.
  float phase = fract(u_time / max(u_loopDur, 0.1));
  float a = phase * 6.2831853;
  vec2 Ldir = vec2(cos(a), sin(a));

  // Directional weight: bright arc where the rim faces the light, falling off to
  // the ambient floor on the far side.
  float align = dot(outward, Ldir);
  float dirW = u_ambient + (1.0 - u_ambient) * pow(max(align, 0.0), 1.5);

  // --- Corona terms (inside the disk) ---
  // Width dial maps to how deep the Fresnel band reaches toward the center.
  float pEff = mix(10.0, 1.5, clamp(u_coronaWidth, 0.0, 1.0));
  float rim = 1.0 - z;              // 0 at center, 1 at silhouette
  float band = pow(rim, pEff);      // main corona
  float edge = pow(rim, 16.0);      // crisp Fresnel line at the very edge
  float scat = pow(rim, 2.0);       // scattered fill, kept off the dark center

  float corona = band * dirW;
  corona += u_fresnel * edge * dirW;
  corona += u_scatter * scat * (0.35 + 0.65 * dirW);
  corona += u_emissive * band;      // self-lit: independent of light direction
  float lum = corona * u_coronaIntensity;

  // --- Palette derived from the single key color (linear space) ---
  vec3 keyLin = toLinear(u_key);
  float keyLuma = dot(keyLin, vec3(0.299, 0.587, 0.114));
  vec3 hotLin = mix(keyLin, vec3(1.0), 0.85);              // near-white hotspot
  vec3 wallColLin = mix(vec3(keyLuma), keyLin, 0.7) * 0.5; // deep desaturated sibling

  // Rim color ramps key -> hot toward the brightest, lit part of the rim.
  float hot = clamp(edge * 1.2 + (dirW - u_ambient) * band, 0.0, 1.0);
  vec3 rimCol = mix(keyLin, hotLin, hot);
  // Hue Spread: analogous drift, warmer toward the light.
  vec3 hsv = rgb2hsv(rimCol);
  hsv.x = fract(hsv.x + u_hueSpread * 0.06 * align);
  rimCol = hsv2rgb(hsv);

  // --- Backdrop wall ---
  float sideGrad = 0.5 + 0.5 * dot(normalize(p + vec2(1.0e-4)), Ldir);
  float radial = mix(1.0, smoothstep(1.5, 0.1, length(p)), 0.35);
  float wallLum = u_wallBright * (0.55 + 0.45 * sideGrad) * (0.75 + 0.45 * radial);
  wallLum *= 1.0 + 0.35 * u_backdropZ;
  vec3 wall = wallColLin * wallLum;

  // --- Outside the disk: bloom halo + contact shadow ---
  float haloWidth = 0.12 + 0.55 * u_bloom;
  float halo = smoothstep(1.0 + haloWidth, 1.0, r);
  halo = pow(halo, 2.0) * dirW;
  vec3 haloCol = mix(keyLin, hotLin, 0.35);

  float contact = 1.0 - smoothstep(1.0, 1.15, r);         // 1 at edge -> 0 outward
  vec3 wallSurf = wall * (1.0 - u_contact * contact) + haloCol * halo * u_bloom;

  // --- Composite: ball occludes the wall; rim carries the light ---
  float px = 1.0 / (R * u_resolution.y);
  float ballMask = smoothstep(1.0 + 1.5 * px, 1.0 - 1.5 * px, r);

  vec3 ballSurf = rimCol * lum;
  vec3 col = mix(wallSurf, ballSurf, ballMask);

  // Bloom blow-out: extra white where the rim goes super-bright.
  col += hotLin * pow(max(lum - 1.0, 0.0), 1.5) * u_bloom * 0.5 * ballMask;

  // Soft filmic clamp keeps highlights from clipping while blacks stay black.
  col = col / (1.0 + col);
  col = toGamma(col);

  // Dither to kill gradient banding on the wall.
  col += (hash21(gl_FragCoord.xy) - 0.5) / 255.0;

  gl_FragColor = vec4(col, 1.0);
}
