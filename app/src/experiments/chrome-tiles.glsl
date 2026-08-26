/**
 * Chrome Tiles — a wall of touching chrome primitives reflecting a liquid
 * pastel environment.
 *
 * Derived from Lea Rosema's "Yet another fork of cheapNoise inception"
 * (codepen.io/learosema/pen/WNpGKpz). The pen paints a domain-warped
 * `cheapNoise` field straight onto the screen with a four-color palette and a
 * `color / (n² + 7n)` tone curve — that curve is what gives it the liquid-
 * chrome streaks. Here the same field is no longer the picture: it is the
 * *environment* being reflected by a tiling of 3D primitives, so the streaks
 * bend around tubes, rings, domes and rounded boxes instead of drifting
 * randomly.
 *
 * Construction (all analytic, Pencil-safe, no raymarching):
 *  1. The canvas is cut into square cells (optionally quadtree-split so big
 *     and small pieces sit side by side). Every primitive fills its cell
 *     edge-to-edge, so neighbours touch with no gaps.
 *  2. Each cell hashes to a primitive + orientation. The primitive's surface
 *     normal is reconstructed from the local cell coordinate (cylinder:
 *     z = sqrt(1 - y²), torus, sphere cap, rounded box bevel, pyramid,
 *     half-pipe, flat plate).
 *  3. The orthographic reflection vector indexes the warped noise field,
 *     which is mapped through the palette + tone curve, then shaded with a
 *     studio horizon, a key-light specular and a fresnel rim. Seams between
 *     cells get a contact-shadow so the pieces read as separate solids.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

// SECTION: Tiling
/**
 * Base size of one primitive cell, in canvas pixels. Cells are always square.
 * @label Cell Size
 * @default 180
 * @range 40, 600
 */
uniform float u_cell;

/**
 * Chance that a cell is quartered into four smaller primitives (applied up to
 * two levels deep). 0 keeps a uniform grid; higher mixes big and small pieces.
 * @label Subdivide
 * @default 0.35
 * @range 0, 1
 */
uniform float u_split;

/**
 * Which primitives appear. "Mixed" draws all of them per cell hash; the
 * others force a single family (with its own hashed orientations).
 * @label Shapes
 * @select Mixed, Tubes, Rings, Domes, Boxes, Pyramids, Half-Pipes, Plates
 * @default 0
 */
uniform float u_shapeSet;

/**
 * Reshuffles which primitive lands in which cell.
 * @label Seed
 * @default 7
 * @range 0, 100
 */
uniform float u_seed;

/**
 * Nudge the tiling across the canvas (fraction of one base cell).
 * @label Offset X
 * @default 0
 * @range -1, 1
 */
uniform float u_offsetX;

/**
 * @label Offset Y
 * @default 0
 * @range -1, 1
 */
uniform float u_offsetY;

// SECTION: Relief
/**
 * How steeply the primitives bulge out of the plane. Low is a soft embossed
 * relief, high is fully round solids.
 * @label Relief
 * @default 1
 * @range 0.2, 2.5
 */
uniform float u_relief;

/**
 * Corner rounding of the box primitive as a fraction of its half-width.
 * 1 turns the box into a full cushion dome.
 * @label Box Rounding
 * @default 0.45
 * @range 0.1, 1
 */
uniform float u_boxRound;

/**
 * Tube thickness of the ring primitive as a fraction of its radius.
 * @label Ring Thickness
 * @default 0.42
 * @range 0.15, 0.6
 */
uniform float u_ringThick;

/**
 * Dark contact shadow along the seams where primitives touch.
 * @label Seam Shadow
 * @default 0.55
 * @range 0, 1
 */
uniform float u_seam;

// SECTION: Palette
/**
 * Base of the reflected environment (the pen's color1).
 * @label Color 1
 * @color
 * @default #ffffff
 */
uniform vec3 u_color1;

/**
 * Tone that fills in where the noise density is high (the pen's color2).
 * @label Color 2
 * @color
 * @default #ffafaf
 */
uniform vec3 u_color2;

/**
 * Tone driven by the first warp layer (the pen's color3).
 * @label Color 3
 * @color
 * @default #0099ff
 */
uniform vec3 u_color3;

/**
 * Tone driven by the second warp layer (the pen's color4).
 * @label Color 4
 * @color
 * @default #aaffff
 */
uniform vec3 u_color4;

/**
 * Overall brightness of the reflected field after the pen's tone curve.
 * @label Exposure
 * @default 2.4
 * @range 0.5, 6
 */
uniform float u_exposure;

// SECTION: Environment
/**
 * How much the noise field is looked up by reflection direction (chrome
 * mirror) versus by screen position (the original pen's flat paint).
 * @label Mirror
 * @default 0.85
 * @range 0, 1
 */
uniform float u_mirror;

/**
 * Zoom of the noise field in the environment (the pen's scale).
 * @label Env Scale
 * @default 0.6
 * @range 0.1, 3
 */
uniform float u_envScale;

/**
 * Frequency multiplier of the cheapNoise sine stack (the pen's ax..aw).
 * @label Noise Detail
 * @default 0.7
 * @range 0.3, 2.5
 */
uniform float u_detail;

/**
 * Domain-warp strength (the pen's bx / by). Higher folds the streaks over
 * themselves.
 * @label Warp
 * @default 1
 * @range -1.5, 1.5
 */
uniform float u_warp;

/**
 * Drift speed of the liquid field.
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
 * Strength of the studio horizon split: bright sky above, dark floor below,
 * on top of the liquid field.
 * @label Horizon
 * @default 0.5
 * @range 0, 1
 */
uniform float u_horizon;

/**
 * Hard key-light highlight on each primitive.
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

const float PI = 3.141592654;

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7)) + u_seed * 17.31) * 43758.5453);
}

float hash31(vec2 p, float k) {
  return fract(sin(dot(p, vec2(269.5, 183.3)) + k * 97.7 + u_seed * 11.13) * 43758.5453);
}

// The pen's "just a bunch of sin & cos" field, verbatim apart from the shared
// frequency multiplier.
float cheapNoise(vec3 stp) {
  vec3 p = vec3(stp.xy, stp.z);
  vec4 a = vec4(5.0, 7.0, 9.0, 13.0) * u_detail;
  return mix(
    sin(p.z + p.x * a.x + cos(p.x * a.x - p.z)) *
      cos(p.z + p.y * a.y + cos(p.y * a.x + p.z)),
    sin(1.0 + p.x * a.z + p.z + cos(p.y * a.w - p.z)) *
      cos(1.0 + p.y * a.w + p.z + cos(p.x * a.x + p.z)),
    0.436
  );
}

/** Liquid environment: warped noise → four-color palette → tone curve. */
vec3 liquidEnv(vec2 st) {
  float t = u_time * u_speed;
  float S = sin(t * 0.05);
  float C = cos(t * 0.05);
  vec2 v1 = vec2(cheapNoise(vec3(st, 2.0)), cheapNoise(vec3(st, 1.0)));
  vec2 v2 = vec2(
    cheapNoise(vec3(st + u_warp * v1 + vec2(C * 1.7, S * 9.2), 0.15 * t)),
    cheapNoise(vec3(st + u_warp * v1 + vec2(S * 8.3, C * 2.8), 0.126 * t))
  );
  float n = 0.5 + 0.5 * cheapNoise(vec3(st + v2, 0.0));

  vec3 color = mix(u_color1, u_color2, clamp(n * n * 8.0, 0.0, 1.0));
  color = mix(color, u_color3, clamp(length(v1), 0.0, 1.0));
  color = mix(color, u_color4, clamp(abs(v2.x), 0.0, 1.0));
  color /= n * n + n * 7.0;
  return color * u_exposure;
}

/**
 * Surface normal of primitive `kind` at local cell coordinate q ∈ [-1,1]².
 * Every primitive spans the full cell so neighbours touch. Returns the
 * unnormalised (slope-scaled) normal; z is positive toward the viewer.
 */
vec3 primitiveNormal(float kind, vec2 q) {
  vec3 n = vec3(0.0, 0.0, 1.0);
  float r = length(q);

  if (kind < 0.5) {
    // Tube along x: cylinder cross-section in y.
    float y = clamp(q.y, -1.0, 1.0);
    n = vec3(0.0, y, sqrt(max(1.0 - y * y, 0.0)));
  } else if (kind < 1.5) {
    // Ring: torus lying flat, outer edge touching the cell boundary.
    float minor = u_ringThick;
    float major = 1.0 - minor;
    float d = (r - major) / minor;
    if (abs(d) < 1.0 && r > 1e-4) {
      vec2 dir = q / r;
      n = vec3(dir * d, sqrt(max(1.0 - d * d, 0.0)));
    }
  } else if (kind < 2.5) {
    // Dome: sphere cap; the corners outside the circle stay flat.
    if (r < 1.0) n = vec3(q, sqrt(max(1.0 - r * r, 0.0)));
  } else if (kind < 3.5) {
    // Rounded box: flat top, quarter-round bevel of radius `b`.
    float b = u_boxRound;
    vec2 e = max(abs(q) - (1.0 - b), 0.0);
    float el = length(e);
    if (el > 1e-4) {
      float s = min(el / b, 1.0);
      n = vec3(sign(q) * (e / el) * s, sqrt(max(1.0 - s * s, 0.0)));
    }
  } else if (kind < 4.5) {
    // Pyramid: four planar faces.
    float slope = 0.9;
    if (abs(q.x) > abs(q.y)) n = vec3(sign(q.x) * slope, 0.0, 1.0);
    else n = vec3(0.0, sign(q.y) * slope, 1.0);
  } else if (kind < 5.5) {
    // Half-pipe: the tube carved inward.
    float y = clamp(q.y, -1.0, 1.0);
    n = vec3(0.0, -y, sqrt(max(1.0 - y * y, 0.0)));
  }
  // kind >= 5.5: plate — flat.
  return n;
}

void main() {
  vec2 frag = gl_FragCoord.xy;
  float cell = max(u_cell, 4.0);
  vec2 p = (frag + vec2(u_offsetX, u_offsetY) * cell) / cell;

  // Quadtree split: up to two hashed subdivisions per base cell.
  float scale = 1.0;
  vec2 id = floor(p);
  for (int i = 0; i < 2; i++) {
    if (hash31(id, 3.0 + float(i)) < u_split) {
      scale *= 2.0;
      id = floor(p * scale);
    }
  }
  vec2 f = fract(p * scale);
  vec2 q = f * 2.0 - 1.0;

  // Per-cell primitive + orientation.
  float kind;
  if (u_shapeSet < 0.5) kind = floor(hash31(id, 1.0) * 6.999);
  else kind = u_shapeSet - 1.0;
  float orient = hash31(id, 2.0);
  vec2 ql = q;
  if (orient < 0.25) ql = vec2(q.y, -q.x);
  else if (orient < 0.5) ql = -q;
  else if (orient < 0.75) ql = vec2(-q.y, q.x);

  vec3 nl = primitiveNormal(kind, ql);
  // Rotate the normal back into screen space with the inverse of `ql`.
  vec2 nxy = nl.xy;
  if (orient < 0.25) nxy = vec2(-nl.y, nl.x);
  else if (orient < 0.5) nxy = -nl.xy;
  else if (orient < 0.75) nxy = vec2(nl.y, -nl.x);
  vec3 n = normalize(vec3(nxy * u_relief, nl.z));

  // Orthographic reflection.
  vec3 v = vec3(0.0, 0.0, 1.0);
  vec3 r = 2.0 * n.z * n - v;

  // Environment lookup: blend between mirror (reflection direction) and the
  // pen's original flat screen-space paint.
  vec2 aspect = vec2(u_resolution.x / u_resolution.y, 1.0);
  vec2 screenSt = (frag / u_resolution) * aspect;
  vec2 mirrorSt = r.xy * 0.28 + screenSt * 0.3;
  vec2 st = mix(screenSt, mirrorSt, u_mirror) * u_envScale * 2.0;
  vec3 env = liquidEnv(st);

  // Studio horizon over the liquid field, oriented by the light angle.
  float la = radians(u_lightAngle);
  vec2 up = vec2(cos(la), sin(la));
  float elev = dot(r.xy, up);
  float horizon = smoothstep(-0.35, 0.35, elev);
  float studio = mix(0.55, 1.35, horizon);
  env *= mix(1.0, studio, u_horizon);

  // Key-light specular + fresnel rim.
  vec3 l = normalize(vec3(up * 0.8, 0.9));
  vec3 h = normalize(l + v);
  float spec = pow(max(dot(n, h), 0.0), 48.0) * u_specular;
  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 4.0) * u_fresnel;

  // Contact shadow along the cell seams, in pixels so it holds at any scale.
  float px = cell / scale;
  vec2 edgeDist = (0.5 - abs(f - 0.5)) * px;
  float seamD = min(edgeDist.x, edgeDist.y);
  float seam = 1.0 - smoothstep(0.0, 6.0 + px * 0.04, seamD);
  seam *= (1.0 - nl.z * 0.5); // flat plates keep a thinner seam
  env *= 1.0 - u_seam * seam * 0.85;

  vec3 col = env + vec3(spec) + vec3(rim) * (0.4 + 0.6 * env);

  // Soft highlight shoulder so the tone curve's spikes roll into white.
  vec3 hi = max(col - 0.8, 0.0);
  col = min(col, vec3(0.8)) + hi / (1.0 + 1.5 * hi);
  col += (hash21(frag) - 0.5) * 0.006;
  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
