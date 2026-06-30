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
 * @label Origin
 * @select Center, Corner, Left, Top, Right, Bottom
 * @default 0
 */
uniform float u_from;

/**
 * @label Direction
 * @select Normal, Alternate
 * @default 0
 */
uniform float u_direction;

/**
 * @label Easing
 * @select Bezier, Spring
 * @default 0
 */
uniform float u_easingType;

/**
 * @label Easing Curve
 * @bezier
 * @default 0.0, 0.0, 0.58, 1.0
 */
uniform vec4 u_bezier;

/**
 * Spring stiffness — higher = faster oscillation.
 * @label Stiffness
 * @default 8.0
 * @range 2, 20
 */
uniform float u_springStiff;

/**
 * Spring damping — lower = more bouncy overshoot.
 * @label Damping
 * @default 5.0
 * @range 1, 15
 */
uniform float u_springDamp;

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

float cubicBezier(float t) {
  float s = t;
  float x1 = u_bezier.x, y1 = u_bezier.y, x2 = u_bezier.z, y2 = u_bezier.w;
  for (int i = 0; i < 8; i++) {
    float inv = 1.0 - s;
    float xS = 3.0 * inv * inv * s * x1 + 3.0 * inv * s * s * x2 + s * s * s;
    float dxS = 3.0 * inv * inv * x1 + 6.0 * inv * s * (x2 - x1) + 3.0 * s * s * (1.0 - x2);
    s -= (xS - t) / max(dxS, 0.001);
    s = clamp(s, 0.0, 1.0);
  }
  float inv = 1.0 - s;
  return 3.0 * inv * inv * s * y1 + 3.0 * inv * s * s * y2 + s * s * s;
}

float springEase(float t) {
  float w = u_springStiff;
  float d = u_springDamp;
  return 1.0 - exp(-d * t) * cos(w * t);
}

float applyEasing(float t) {
  t = clamp(t, 0.0, 1.0);
  float mode = floor(u_easingType + 0.5);
  if (mode < 0.5) return cubicBezier(t);
  return clamp(springEase(t), 0.0, 1.5);
}

float computeStagger(vec2 cellID, vec2 grid) {
  float from = floor(u_from + 0.5);
  vec2 origin;
  float maxDist;

  if (from < 0.5) {
    origin = (grid - 1.0) * 0.5;
  } else if (from < 1.5) {
    origin = vec2(0.0);
  } else if (from < 2.5) {
    origin = vec2(0.0, (grid.y - 1.0) * 0.5);
    float dist = abs(cellID.x - origin.x);
    return dist / max(grid.x - 1.0, 1.0);
  } else if (from < 3.5) {
    origin = vec2((grid.x - 1.0) * 0.5, 0.0);
    float dist = abs(cellID.y - origin.y);
    return dist / max(grid.y - 1.0, 1.0);
  } else if (from < 4.5) {
    origin = vec2(grid.x - 1.0, (grid.y - 1.0) * 0.5);
    float dist = abs(cellID.x - origin.x);
    return dist / max(grid.x - 1.0, 1.0);
  } else {
    origin = vec2((grid.x - 1.0) * 0.5, grid.y - 1.0);
    float dist = abs(cellID.y - origin.y);
    return dist / max(grid.y - 1.0, 1.0);
  }

  maxDist = length(origin);
  float dist = length(cellID - origin);
  return dist / max(maxDist, 0.001);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;

  vec2 grid = vec2(floor(u_cols), floor(u_rows));
  vec2 cellID = floor(uv * grid);
  vec2 cellUV = fract(uv * grid);

  float staggerT = computeStagger(cellID, grid);

  // jitter
  float jitterOffset = hash(cellID) * u_jitter;
  staggerT = clamp(staggerT + jitterOffset, 0.0, 1.0);

  // ease the stagger distribution
  staggerT = applyEasing(staggerT);

  // alternate: ping-pong the cycle
  float isAlternate = floor(u_direction + 0.5);
  float cycleLen = 2.0 + u_stagger;
  float rawTime = u_time * u_speed - staggerT * u_stagger;

  float pingPongLen = cycleLen * 2.0;
  float phase = mod(rawTime, mix(cycleLen, pingPongLen, isAlternate));
  float localTime = mix(
    mod(rawTime, cycleLen),
    phase < cycleLen ? phase : pingPongLen - phase,
    isAlternate
  );

  // per-dot animation
  float appear = clamp(localTime / 0.5, 0.0, 1.0);
  float disappear = clamp((localTime - (cycleLen - 0.5)) / 0.5, 0.0, 1.0);
  float anim = applyEasing(appear) * (1.0 - applyEasing(disappear));

  // dot
  float radius = u_dotSize * 0.5 * anim;
  vec2 cellCenter = cellUV - 0.5;
  float cellAspect = (u_resolution.x / grid.x) / (u_resolution.y / grid.y);
  cellCenter.x *= cellAspect;

  float d = length(cellCenter);
  float dot = smoothstep(radius, radius - 0.02, d);

  // color
  vec3 col = mix(u_colorA, u_colorB, staggerT);
  col *= 0.8 + 0.2 * anim;

  vec3 bg = vec3(0.05);
  vec3 final = mix(bg, col, dot);

  gl_FragColor = vec4(final, 1.0);
}
