/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * Number of columns in the grid.
 * @label Columns
 * @default 10.0
 * @range 2, 24
 */
uniform float u_cols;

/**
 * Number of rows in the grid.
 * @label Rows
 * @default 8.0
 * @range 2, 18
 */
uniform float u_rows;

/**
 * How much time offset spreads across the grid (seconds).
 * @label Stagger
 * @default 0.6
 * @range 0, 2
 */
uniform float u_stagger;

/**
 * Dot size relative to cell. 0 = invisible, 1 = fills cell.
 * @label Dot Size
 * @default 0.7
 * @range 0.1, 1
 */
uniform float u_dotSize;

/**
 * Animation speed.
 * @label Speed
 * @default 1.5
 * @range 0.2, 5
 */
uniform float u_speed;

/**
 * How much random offset per cell (0 = pure stagger, 1 = noisy).
 * @label Jitter
 * @default 0.0
 * @range 0, 1
 */
uniform float u_jitter;

/**
 * @label Color A
 * @color
 * @default #6c5ce7
 */
uniform vec3 u_colorA;

/**
 * @label Color B
 * @color
 * @default #00cec9
 */
uniform vec3 u_colorB;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float easeOutCubic(float t) {
  float f = 1.0 - t;
  return 1.0 - f * f * f;
}

float easeInOutQuad(float t) {
  return t < 0.5 ? 2.0 * t * t : 1.0 - 2.0 * (1.0 - t) * (1.0 - t);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;

  vec2 grid = vec2(floor(u_cols), floor(u_rows));
  vec2 cellID = floor(uv * grid);
  vec2 cellUV = fract(uv * grid);

  // stagger: distance from center → time offset
  vec2 center = (grid - 1.0) * 0.5;
  float maxDist = length(center);
  float dist = length(cellID - center);
  float staggerT = dist / max(maxDist, 0.001);

  // add jitter: per-cell random offset
  float jitterOffset = hash(cellID) * u_jitter;
  staggerT = clamp(staggerT + jitterOffset, 0.0, 2.0);

  // local time with stagger offset — loops every ~4s
  float cycleLen = 2.0 + u_stagger;
  float localTime = mod(u_time * u_speed - staggerT * u_stagger, cycleLen);

  // animation: 0→1 appear, hold, 1→0 disappear
  float appear = clamp(localTime / 0.5, 0.0, 1.0);
  float disappear = clamp((localTime - (cycleLen - 0.5)) / 0.5, 0.0, 1.0);
  float anim = easeOutCubic(appear) * (1.0 - easeInOutQuad(disappear));

  // dot: circle in each cell, scaled by animation
  float radius = u_dotSize * 0.5 * anim;
  vec2 cellCenter = cellUV - 0.5;

  // correct for non-square cells
  float cellAspect = (u_resolution.x / grid.x) / (u_resolution.y / grid.y);
  cellCenter.x *= cellAspect;

  float d = length(cellCenter);
  float dot = smoothstep(radius, radius - 0.02, d);

  // color: blend A→B based on stagger distance
  float colorT = easeInOutQuad(staggerT);
  vec3 col = mix(u_colorA, u_colorB, colorT);

  // subtle brightness pulse per dot
  col *= 0.8 + 0.2 * anim;

  // background
  vec3 bg = vec3(0.05);
  vec3 final = mix(bg, col, dot);

  gl_FragColor = vec4(final, 1.0);
}
