/**
 * Liquid Chrome — one 3D primitive filling the canvas, reflecting a studio
 * environment with a gentle liquid ripple.
 *
 * Started from Lea Rosema's "Yet another fork of cheapNoise inception"
 * (codepen.io/learosema/pen/WNpGKpz). The pen paints its domain-warped
 * `cheapNoise` field straight onto the screen; used as a reflection that
 * reads as boiling soup, not metal. Real chrome reflects *structure*: a dark
 * floor, a glowing horizon line, a bright sky and a few softbox stripes. So
 * that studio is the environment here, and the pen's warped field survives
 * only as a low-frequency ripple of the lookup direction (Liquid).
 *
 * Construction (all analytic, Pencil-safe, no raymarching): the primitive's
 * surface normal is reconstructed from the canvas coordinate (cylinder:
 * z = sqrt(1 - y²), torus, sphere cap, rounded-box bevel, pyramid faces). The
 * orthographic reflection vector becomes (elevation, azimuth) in a frame
 * oriented by the light angle, which indexes the studio; then a key-light
 * specular and a fresnel rim. Where a primitive doesn't cover the canvas
 * (outside a ring or dome) a flat chrome plate fills in, so the fill is
 * always full-quad.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Shape
/**
 * Which primitive fills the canvas.
 * @label Primitive
 * @select Tube, Ring, Dome, Box, Pyramid, Half-Pipe, Plate
 * @default 0
 */
uniform float u_shape;

/**
 * Rotation of the primitive in the canvas plane, degrees.
 * @label Rotation
 * @default 0
 * @range 0, 360
 */
uniform float u_rotation;

/**
 * Scale of the primitive relative to the canvas. 1 fits the short side;
 * larger crops into the surface, smaller leaves a flat chrome border.
 * @label Size
 * @default 1
 * @range 0.3, 2.5
 */
uniform float u_size;

/**
 * Stretch along the primitive's own x axis (before rotation). 1 is square;
 * "Fill" mode stretches the box / pyramid / plate to the canvas instead.
 * @label Stretch
 * @default 1
 * @range 0.3, 3
 */
uniform float u_stretch;

/**
 * Stretch the box, pyramid and plate to the full canvas aspect instead of
 * using Size + Stretch.
 * @label Fill Canvas
 * @switch
 * @default true
 */
uniform float u_fill;

// SECTION: Relief
/**
 * How steeply the surface bulges out of the plane. Low is a soft embossed
 * relief, high is a fully round solid.
 * @label Relief
 * @default 1
 * @range 0.2, 2.5
 */
uniform float u_relief;

/**
 * Corner rounding of the box as a fraction of its half-width. 1 turns the
 * box into a full cushion dome.
 * @label Box Rounding
 * @default 0.45
 * @range 0.1, 1
 */
uniform float u_boxRound;

/**
 * Tube thickness of the ring as a fraction of its radius.
 * @label Ring Thickness
 * @default 0.42
 * @range 0.15, 0.6
 */
uniform float u_ringThick;

/**
 * Dark contact shadow where the primitive meets the flat plate around it.
 * @label Contact Shadow
 * @default 0.5
 * @range 0, 1
 */
uniform float u_contact;

// SECTION: Palette
/**
 * Sky / highlight tone of the reflected studio.
 * @label Sky
 * @color
 * @default #ffffff
 */
uniform vec3 u_color1;

/**
 * Glow tone just above the horizon line.
 * @label Horizon Glow
 * @color
 * @default #ffafaf
 */
uniform vec3 u_color2;

/**
 * Ground / floor tone below the horizon.
 * @label Ground
 * @color
 * @default #1a2436
 */
uniform vec3 u_color3;

/**
 * Tint of the softbox stripes.
 * @label Stripe
 * @color
 * @default #aaffff
 */
uniform vec3 u_color4;

/**
 * Overall brightness of the reflected environment.
 * @label Exposure
 * @default 1
 * @range 0.2, 3
 */
uniform float u_exposure;

// SECTION: Environment
/**
 * How much the environment is looked up by reflection direction (true
 * mirror) versus by screen position (flat, painted-on).
 * @label Mirror
 * @default 0.9
 * @range 0, 1
 */
uniform float u_mirror;

/**
 * Virtual-camera perspective. 0 is a flat orthographic mirror; higher sweeps
 * the environment across flat faces (the diagonal streaks of chrome plates).
 * @label Perspective
 * @default 0.4
 * @range 0, 1
 */
uniform float u_persp;

/**
 * Sharpness of the sky/ground divide — the classic chrome horizon line.
 * @label Horizon Sharpness
 * @default 0.7
 * @range 0, 1
 */
uniform float u_horizonSharp;

/**
 * Shifts the horizon: negative shows more dark ground on flat faces,
 * positive more sky.
 * @label Horizon Tilt
 * @default 0.1
 * @range -1, 1
 */
uniform float u_tilt;

/**
 * Number of softbox stripes around the environment. 0 disables.
 * @label Stripes
 * @default 3
 * @range 0, 12
 */
uniform float u_stripes;

/**
 * Width of each softbox stripe as a fraction of its cell.
 * @label Stripe Width
 * @default 0.3
 * @range 0.05, 0.9
 */
uniform float u_stripeWidth;

/**
 * Edge softness of the stripes. 0 is hard studio flags.
 * @label Stripe Softness
 * @default 0.35
 * @range 0, 1
 */
uniform float u_stripeSoft;

/**
 * Brightness of the stripes.
 * @label Stripe Strength
 * @default 0.8
 * @range 0, 1.5
 */
uniform float u_stripeAmt;

/**
 * Liquid ripple of the environment (the pen's warped cheapNoise, applied as
 * a gentle low-frequency distortion of the reflection instead of as the
 * picture). 0 is a perfectly still studio.
 * @label Liquid
 * @default 0.25
 * @range 0, 1
 */
uniform float u_warp;

/**
 * Spatial scale of the liquid ripple. Lower is broader, calmer waves.
 * @label Liquid Scale
 * @default 0.35
 * @range 0.1, 1.5
 */
uniform float u_detail;

/**
 * Drift speed of the liquid ripple.
 * @label Speed
 * @default 0.35
 * @range 0, 2
 */
uniform float u_speed;

// SECTION: Lighting
/**
 * Screen direction the key light comes from, degrees.
 * @label Light Angle
 * @default 120
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * Hard key-light highlight.
 * @label Specular
 * @default 0.6
 * @range 0, 2
 */
uniform float u_specular;

/**
 * Grazing-angle edge glow.
 * @label Edge Shine
 * @default 0.5
 * @range 0, 2
 */
uniform float u_fresnel;

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The pen's "just a bunch of sin & cos" field, verbatim.
float cheapNoise(vec3 stp) {
  vec3 p = vec3(stp.xy, stp.z);
  vec4 a = vec4(5.0, 7.0, 9.0, 13.0);
  return mix(
    sin(p.z + p.x * a.x + cos(p.x * a.x - p.z)) *
      cos(p.z + p.y * a.y + cos(p.y * a.x + p.z)),
    sin(1.0 + p.x * a.z + p.z + cos(p.y * a.w - p.z)) *
      cos(1.0 + p.y * a.w + p.z + cos(p.x * a.x + p.z)),
    0.436
  );
}

/** Gentle 2D ripple from the pen's warped cheapNoise field. */
vec2 liquidRipple(vec2 st) {
  float t = u_time * u_speed;
  float S = sin(t * 0.05);
  float C = cos(t * 0.05);
  vec2 v1 = vec2(cheapNoise(vec3(st, 2.0)), cheapNoise(vec3(st, 1.0)));
  vec2 v2 = vec2(
    cheapNoise(vec3(st + 0.5 * v1 + vec2(C * 1.7, S * 9.2), 0.15 * t)),
    cheapNoise(vec3(st + 0.5 * v1 + vec2(S * 8.3, C * 2.8), 0.126 * t))
  );
  return v2;
}

/**
 * Studio environment for a reflection vector: dark ground, glowing horizon
 * line, bright sky, and vertical softbox stripes — the bands real chrome
 * reflects. `elev` is signed height above the horizon, `azim` the angle
 * around the vertical axis.
 */
vec3 studioEnv(float elev, float azim) {
  float soft = mix(0.4, 0.01, u_horizonSharp);
  float horizon = smoothstep(-soft, soft, elev);

  // Sky: brightest just above the horizon, easing toward the zenith.
  float skyT = clamp(elev, 0.0, 1.0);
  vec3 sky = mix(u_color2, u_color1 * 0.62, smoothstep(0.0, 0.3, skyT));
  sky *= mix(1.0, 0.75, smoothstep(0.3, 1.0, skyT));
  // Ground: darkest straight down, lifting slightly toward the horizon.
  float gT = clamp(-elev, 0.0, 1.0);
  vec3 ground = u_color3 * mix(1.0, 0.3, gT);
  vec3 env = mix(ground, sky, horizon);

  // Softbox stripes around the azimuth, above the horizon only.
  if (u_stripes > 0.5) {
    float phase = azim * u_stripes * 0.15915494309; // /2π
    float local = abs(fract(phase) - 0.5);
    float hw = u_stripeWidth * 0.5;
    float feather = mix(0.005, 0.2, u_stripeSoft);
    float stripe = 1.0 - smoothstep(hw - feather, hw + feather, local);
    env += u_color4 * stripe * u_stripeAmt * horizon;
  }
  return env * u_exposure;
}

/**
 * Surface normal of the primitive at local coordinate q, where the primitive
 * spans [-ext, ext]. Returns the unnormalised normal (z toward the viewer)
 * and writes the signed distance to the primitive's silhouette (in q units,
 * negative inside) to `edge` for the contact shadow.
 */
vec3 primitiveNormal(vec2 q, vec2 ext, out float edge) {
  vec3 n = vec3(0.0, 0.0, 1.0);
  edge = 1.0;
  vec2 qn = q / ext; // unit-square coordinates
  float r = length(qn);

  if (u_shape < 0.5) {
    // Tube along x: cylinder cross-section in y, runs edge-to-edge in x.
    float y = clamp(qn.y, -1.0, 1.0);
    n = vec3(0.0, y, sqrt(max(1.0 - y * y, 0.0)));
    edge = (abs(qn.y) - 1.0) * ext.y;
  } else if (u_shape < 1.5) {
    // Ring: torus lying flat.
    float minor = u_ringThick;
    float major = 1.0 - minor;
    float d = (r - major) / minor;
    if (abs(d) < 1.0 && r > 1e-4) {
      vec2 dir = qn / r;
      n = vec3(dir * d, sqrt(max(1.0 - d * d, 0.0)));
    }
    edge = (abs(r - major) - minor) * ext.x;
  } else if (u_shape < 2.5) {
    // Dome: sphere cap.
    if (r < 1.0) n = vec3(qn, sqrt(max(1.0 - r * r, 0.0)));
    edge = (r - 1.0) * ext.x;
  } else if (u_shape < 3.5) {
    // Rounded box: flat top, quarter-round bevel of radius `b` (in units of
    // the shorter half-extent so corners stay circular when stretched).
    float b = u_boxRound * min(ext.x, ext.y);
    vec2 inner = ext - b;
    vec2 e = max(abs(q) - inner, 0.0);
    float el = length(e);
    if (el > 1e-4) {
      float s = min(el / b, 1.0);
      n = vec3(sign(q) * (e / el) * s, sqrt(max(1.0 - s * s, 0.0)));
    }
    edge = el - b;
  } else if (u_shape < 4.5) {
    // Pyramid: four planar faces meeting at the centre.
    float slope = 0.9;
    vec2 a = abs(qn);
    if (a.x > a.y) n = vec3(sign(q.x) * slope, 0.0, 1.0);
    else n = vec3(0.0, sign(q.y) * slope, 1.0);
    edge = (max(a.x, a.y) - 1.0) * min(ext.x, ext.y);
  } else if (u_shape < 5.5) {
    // Half-pipe: the tube carved inward.
    float y = clamp(qn.y, -1.0, 1.0);
    n = vec3(0.0, -y, sqrt(max(1.0 - y * y, 0.0)));
    edge = (abs(qn.y) - 1.0) * ext.y;
  }
  // u_shape >= 5.5: plate — flat.
  return n;
}

void main() {
  vec2 frag = gl_FragCoord.xy;
  vec2 res = u_resolution;
  float shortSide = min(res.x, res.y);

  // Canvas coordinate with the short side spanning [-1, 1].
  vec2 c = (frag - 0.5 * res) / (0.5 * shortSide);

  // Rotate into the primitive's local frame.
  float ang = radians(u_rotation);
  float ca = cos(ang);
  float sa = sin(ang);
  vec2 q = vec2(ca * c.x + sa * c.y, -sa * c.x + ca * c.y);

  // Primitive half-extents in local units.
  vec2 ext = vec2(u_stretch, 1.0) * u_size;
  bool fillable = u_shape > 2.5; // box, pyramid, plate (+ half-pipe/tube run edge-to-edge anyway)
  if (u_fill > 0.5 && fillable) {
    // Stretch to the rotated canvas: extents of the canvas rectangle projected
    // onto the local axes.
    vec2 hs = res / shortSide;
    ext = vec2(abs(ca) * hs.x + abs(sa) * hs.y, abs(sa) * hs.x + abs(ca) * hs.y);
  }
  if (u_shape < 0.5 || (u_shape > 4.5 && u_shape < 5.5)) {
    // Tube / half-pipe: run the full canvas length along x regardless.
    ext.x = 1e4;
  }

  float edge;
  vec3 nl = primitiveNormal(q, ext, edge);
  // Rotate the normal back into screen space.
  vec2 nxy = vec2(ca * nl.x - sa * nl.y, sa * nl.x + ca * nl.y);
  vec3 n = normalize(vec3(nxy * u_relief, nl.z));

  // View ray from a virtual camera above the canvas centre; u_persp = 0
  // degenerates to the straight-on orthographic view.
  vec3 v = normalize(vec3(-c * u_persp, 1.0));
  vec3 r = 2.0 * dot(n, v) * n - v;

  // Reflection → (elevation, azimuth) in the light-oriented frame, blended
  // with screen position for the flat "painted-on" look.
  float la = radians(u_lightAngle);
  vec2 up = vec2(cos(la), sin(la));
  vec2 side = vec2(-up.y, up.x);
  vec2 aspect = vec2(res.x / res.y, 1.0);
  vec2 screenC = ((frag / res) - 0.5) * aspect * 2.0;
  vec2 dir = mix(screenC, r.xy, u_mirror);
  float depth = mix(0.3, r.z, u_mirror);

  // Liquid ripple: low-frequency distortion of the lookup direction.
  vec2 st = (screenC * 0.5 + r.xy * 0.25) * u_detail;
  vec2 ripple = liquidRipple(st) * u_warp * 0.35;
  dir += ripple;

  float elev = dot(dir, up) + u_tilt;
  // Floor the depth so the azimuth has no pole (no stripes whirling into a point).
  float azim = atan(dot(dir, side), max(depth, 0.0) + 0.5);
  vec3 env = studioEnv(elev, azim);

  // Steep slopes reflect back toward the viewer — a dark room, not the sky.
  float back = clamp(-r.z, 0.0, 1.0);
  env *= mix(1.0, 0.2, back * back * 0.9);

  // Key-light specular + fresnel rim.
  vec3 l = normalize(vec3(up * 0.8, 0.9));
  vec3 h = normalize(l + v);
  float spec = pow(max(dot(n, h), 0.0), 48.0) * u_specular;
  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 4.0) * u_fresnel;

  // Contact shadow on the flat plate just outside the primitive's silhouette,
  // measured in pixels so it holds at any canvas size.
  float edgePx = edge * 0.5 * shortSide;
  float contact = (1.0 - smoothstep(0.0, 18.0, edgePx)) * step(0.0, edgePx);
  env *= 1.0 - u_contact * contact * 0.7;

  vec3 col = env + vec3(spec) + vec3(rim) * (0.4 + 0.6 * env);

  // Soft highlight shoulder so the tone curve's spikes roll into white.
  vec3 hi = max(col - 0.8, 0.0);
  col = min(col, vec3(0.8)) + hi / (1.0 + 1.5 * hi);
  col += (hash21(frag) - 0.5) * 0.006;
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
