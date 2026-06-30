/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/**
 * Number of columns in the grid.
 * @section Grid
 * @label Columns
 * @default 10.0
 * @range 2, 24
 */
uniform float u_cols;

/**
 * Number of rows in the grid.
 * @section Grid
 * @label Rows
 * @default 8.0
 * @range 2, 18
 */
uniform float u_rows;

/**
 * Dot size relative to cell. 0 = invisible, 1 = fills cell.
 * @section Grid
 * @label Dot Size
 * @default 0.7
 * @range 0.1, 1
 */
uniform float u_dotSize;

/**
 * Where the stagger ripple originates.
 * @section Stagger
 * @label Origin
 * @select Center, Corner, Left, Top, Right, Bottom
 * @default 0
 */
uniform float u_from;

/**
 * How much time offset spreads across the grid (seconds).
 * @section Stagger
 * @label Amount
 * @default 0.6
 * @range 0, 2
 */
uniform float u_stagger;

/**
 * How much random offset per cell (0 = pure stagger, 1 = noisy).
 * @section Stagger
 * @label Jitter
 * @default 0.0
 * @range 0, 1
 */
uniform float u_jitter;

/**
 * Controls the stagger distribution — how timing spreads across the grid.
 * @section Stagger Easing
 * @label Type
 * @select Bezier, Spring, Bounce, Elastic
 * @default 0
 */
uniform float u_staggerEaseType;

/**
 * Shapes the stagger timing curve.
 * @section Stagger Easing
 * @label Curve
 * @bezier
 * @default 0.0, 0.0, 0.58, 1.0
 */
uniform vec4 u_staggerBezier;

/**
 * Spring stiffness — higher = faster oscillation.
 * @section Stagger Easing
 * @label Stiffness
 * @default 8.0
 * @range 2, 20
 */
uniform float u_springStiff;

/**
 * Spring / elastic damping — lower = more bouncy.
 * @section Stagger Easing
 * @label Damping
 * @default 5.0
 * @range 1, 15
 */
uniform float u_springDamp;

/**
 * Controls the per-dot appear/disappear animation curve.
 * @section Dot Easing
 * @label Type
 * @select Bezier, Spring, Bounce, Elastic
 * @default 0
 */
uniform float u_dotEaseType;

/**
 * Shapes the dot animation curve.
 * @section Dot Easing
 * @label Curve
 * @bezier
 * @default 0.16, 1.0, 0.3, 1.0
 */
uniform vec4 u_dotBezier;

/**
 * Animation speed.
 * @section Playback
 * @label Speed
 * @default 1.5
 * @range 0.2, 5
 */
uniform float u_speed;

/**
 * @section Playback
 * @label Direction
 * @select Normal, Alternate
 * @default 0
 */
uniform float u_direction;

/**
 * @section Color
 * @label Color A
 * @color
 * @default #6c5ce7
 */
uniform vec3 u_colorA;

/**
 * @section Color
 * @label Color B
 * @color
 * @default #00cec9
 */
uniform vec3 u_colorB;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cubicBezier(float t, vec4 cp) {
  float s = t;
  float x1 = cp.x, y1 = cp.y, x2 = cp.z, y2 = cp.w;
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
  return 1.0 - exp(-u_springDamp * t) * cos(u_springStiff * t);
}

float bounceEase(float t) {
  float n = 7.5625;
  float d = 2.75;
  float it = 1.0 - t;
  float b;
  if (it < 1.0 / d) {
    b = n * it * it;
  } else if (it < 2.0 / d) {
    float p = it - 1.5 / d;
    b = n * p * p + 0.75;
  } else if (it < 2.5 / d) {
    float p = it - 2.25 / d;
    b = n * p * p + 0.9375;
  } else {
    float p = it - 2.625 / d;
    b = n * p * p + 0.984375;
  }
  return 1.0 - b;
}

float elasticEase(float t) {
  if (t <= 0.0) return 0.0;
  if (t >= 1.0) return 1.0;
  float p = u_springDamp * 0.1;
  float s = p * 0.25;
  return pow(2.0, -10.0 * t) * sin((t - s) * 6.2832 / p) + 1.0;
}

float easeByType(float t, float mode, vec4 bezierCp) {
  t = clamp(t, 0.0, 1.0);
  float m = floor(mode + 0.5);
  if (m < 0.5) return cubicBezier(t, bezierCp);
  if (m < 1.5) return clamp(springEase(t), 0.0, 1.5);
  if (m < 2.5) return bounceEase(t);
  return clamp(elasticEase(t), -0.5, 1.5);
}

float computeStagger(vec2 cellID, vec2 grid) {
  float from = floor(u_from + 0.5);
  vec2 origin;

  if (from < 0.5) {
    origin = (grid - 1.0) * 0.5;
  } else if (from < 1.5) {
    origin = vec2(0.0);
  } else if (from < 2.5) {
    return abs(cellID.x) / max(grid.x - 1.0, 1.0);
  } else if (from < 3.5) {
    return abs(cellID.y) / max(grid.y - 1.0, 1.0);
  } else if (from < 4.5) {
    return abs(cellID.x - (grid.x - 1.0)) / max(grid.x - 1.0, 1.0);
  } else {
    return abs(cellID.y - (grid.y - 1.0)) / max(grid.y - 1.0, 1.0);
  }

  float maxDist = length(origin);
  return length(cellID - origin) / max(maxDist, 0.001);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;

  vec2 grid = vec2(floor(u_cols), floor(u_rows));
  vec2 cellID = floor(uv * grid);
  vec2 cellUV = fract(uv * grid);

  float staggerT = computeStagger(cellID, grid);

  // jitter
  staggerT = clamp(staggerT + hash(cellID) * u_jitter, 0.0, 1.0);

  // ease the stagger distribution
  staggerT = easeByType(staggerT, u_staggerEaseType, u_staggerBezier);

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

  // per-dot animation with separate easing
  float appear = clamp(localTime / 0.5, 0.0, 1.0);
  float disappear = clamp((localTime - (cycleLen - 0.5)) / 0.5, 0.0, 1.0);
  float anim = easeByType(appear, u_dotEaseType, u_dotBezier)
             * (1.0 - easeByType(disappear, u_dotEaseType, u_dotBezier));

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
