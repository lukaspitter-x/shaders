/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @sdf */
uniform sampler2D u_shape;

/**
 * How fast the colors move.
 * @label Speed
 * @default 0.5
 * @range 0, 2
 */
uniform float u_speed;

/**
 * @label Color 1
 * @color
 * @default #001417
 */
uniform vec3 u_color1;

/**
 * @label Color 2
 * @color
 * @default #0d6b7a
 */
uniform vec3 u_color2;

/**
 * @label Color 3
 * @color
 * @default #3bdcff
 */
uniform vec3 u_color3;

/**
 * @label Color 4
 * @color
 * @default #d9f7ff
 */
uniform vec3 u_color4;

/**
 * Direction the colors flow, in degrees.
 * @label Flow Direction
 * @default 45
 * @range 0, 360
 */
uniform float u_gradientAngle;

/**
 * Overall scale of the color field.
 * @label Scale
 * @default 1.8
 * @range 0.1, 4
 */
uniform float u_scale;

/**
 * How hard each iteration pushes the coordinates around.
 * @label Turbulence
 * @default 0.48
 * @range 0, 2
 */
uniform float u_turbAmp;

/**
 * Spatial frequency of the swirling.
 * @label Swirl Frequency
 * @default 1.4
 * @range 0.1, 4
 */
uniform float u_turbFreq;

/**
 * Frequency of the color bands in the final field.
 * @label Band Frequency
 * @default 1.6
 * @range 0.1, 4
 */
uniform float u_waveFreq;

/**
 * How far from the edge the light bends inward.
 * @label Edge Width
 * @default 0.03
 * @range 0.005, 0.05
 */
uniform float u_edgeDistance;

/**
 * How strongly the edge bends the reflected colors.
 * @label Reflection
 * @default 0.5
 * @range 0, 2
 */
uniform float u_reflection;

/**
 * How strongly the edge is pushed toward the last palette color.
 * @label Edge Highlight
 * @default 0.6
 * @range 0, 1
 */
uniform float u_contourStrength;

vec3 toLinear(vec3 c) {
  return pow(c, vec3(2.2));
}

vec3 toGamma(vec3 c) {
  return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

vec3 oklab(vec3 lin) {
  const mat3 im1 = mat3(0.4121656120, 0.2118591070, 0.0883097947,
      0.5362752080, 0.6807189584, 0.2818474174,
      0.0514575653, 0.1074065790, 0.6302613616);

  const mat3 im2 = mat3(+0.2104542553, +1.9779984951, +0.0259040371,
      +0.7936177850, -2.4285922050, +0.7827717662,
      -0.0040720468, +0.4505937099, -0.8086757660);

  vec3 lms = im1 * lin;
  return im2 * (sign(lms) * pow(abs(lms), vec3(1.0 / 3.0)));
}

vec3 unoklab(vec3 lab) {
  const mat3 m1 = mat3(+1.000000000, +1.000000000, +1.000000000,
      +0.396337777, -0.105561346, -0.089484178,
      +0.215803757, -0.063854173, -1.291485548);

  const mat3 m2 = mat3(+4.076724529, -1.268143773, -0.004111989,
      -3.307216883, +2.609332323, -0.703476310,
      +0.230759054, -0.341134429, +1.706862569);

  vec3 lms = m1 * lab;
  return m2 * (lms * lms * lms);
}

// By Inigo Quilez, under MIT license — https://www.shadertoy.com/view/ttcyRS
vec3 oklabMix(vec3 lin1, vec3 lin2, float t) {
  const mat3 coneToLms = mat3(
      0.4121656120, 0.2118591070, 0.0883097947,
      0.5362752080, 0.6807189584, 0.2818474174,
      0.0514575653, 0.1074065790, 0.6302613616);

  const mat3 lmsToCone = mat3(
      4.0767245293, -1.2681437731, -0.0041119885,
      -3.3072168827, 2.6093323231, -0.7034763098,
      0.2307590544, -0.3411344290, 1.7068625689);

  vec3 lms1 = pow(coneToLms * lin1, vec3(1.0 / 3.0));
  vec3 lms2 = pow(coneToLms * lin2, vec3(1.0 / 3.0));
  vec3 lms = mix(lms1, lms2, t);

  lms *= 1.0 + 0.2 * t * (1.0 - t);

  return lmsToCone * (lms * lms * lms);
}

bool inGamut(vec3 lin) {
  return max(max(lin.r, lin.g), lin.b) <= 1.0 && min(min(lin.r, lin.g), lin.b) >= 0.0;
}

vec3 fitGamut(vec3 lin) {
  if (inGamut(lin)) {
    return lin;
  }
  vec3 lab = oklab(max(lin, 0.0));
  lab.x = clamp(lab.x, 0.0, 1.0);

  float lo = 0.0;
  float hi = 1.0;
  for (int i = 0; i < 6; i++) {
    float mid = 0.5 * (lo + hi);
    if (inGamut(unoklab(vec3(lab.x, lab.yz * mid)))) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return clamp(unoklab(vec3(lab.x, lab.yz * lo)), 0.0, 1.0);
}

vec3 palette(float v) {
  float x = clamp(v, 0.0, 1.0) * 3.0;
  float seg = min(floor(x), 2.0);
  float t = x - seg;
  t = t * t * (3.0 - 2.0 * t);

  if (seg >= 2.0) {
    return oklabMix(toLinear(u_color3), toLinear(u_color4), t);
  }
  if (seg >= 1.0) {
    return oklabMix(toLinear(u_color2), toLinear(u_color3), t);
  }
  return oklabMix(toLinear(u_color1), toLinear(u_color2), t);
}

float colorField(vec2 p, float t) {
  vec2 q = p * u_scale;

  vec2 acc = vec2(0.0);
  for (int i = 0; i < 4; i++) {
    float fi = float(i) + 2.0;
    q += u_turbAmp * sin(length(q) * u_turbFreq * fi - t + acc) / fi;
    acc.x += cos(fi + acc.y * 0.7 + q.x * 1.6 + t);
    acc.y += sin(q.y * (fi + 0.5) + acc.x + t);
  }

  float phase = length(q + acc.yx * 0.25) * u_waveFreq;
  float val = 0.5 + 0.5 * sin(phase) + 0.16 * sin(phase * 2.3 + 1.7);
  return clamp(val, 0.0, 1.0);
}

float fieldAt(vec2 uv, float t) {
  vec2 p = (uv - 0.5) * 2.0;
  p.x *= u_resolution.x / u_resolution.y;

  float ang = radians(u_gradientAngle);
  float c = cos(ang);
  float s = sin(ang);
  p = mat2(c, -s, s, c) * p;

  return colorField(p, t);
}

vec4 cubic(float v) {
  vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
  vec4 s = n * n * n;
  float x = s.x;
  float y = s.y - 4.0 * s.x;
  float z = s.z - 4.0 * s.y + 6.0 * s.x;
  return vec4(x, y, z, 6.0 - x - y - z) / 6.0;
}

vec4 sdfBicubic(vec2 uv, vec2 size) {
  vec2 coord = uv * size - 0.5;
  vec2 frac = fract(coord);
  coord -= frac;

  vec4 wx = cubic(frac.x);
  vec4 wy = cubic(frac.y);

  vec4 centers = coord.xxyy + vec2(-0.5, 1.5).xyxy;
  vec4 weight = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
  vec4 uvs = (centers + vec4(wx.yw, wy.yw) / weight) / size.xxyy;

  vec4 a = texture2D(u_shape, uvs.xz);
  vec4 b = texture2D(u_shape, uvs.yz);
  vec4 c = texture2D(u_shape, uvs.xw);
  vec4 d = texture2D(u_shape, uvs.yw);

  float mx = weight.x / (weight.x + weight.y);
  float my = weight.z / (weight.z + weight.w);
  return mix(mix(d, c, mx), mix(b, a, mx), my);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float t = u_time * u_speed;

  vec4 sdf = sdfBicubic(uv, vec2(textureSize(u_shape, 0)));
  float depth = sdf.r;

  float reach = max(u_edgeDistance * u_resolution.y, 1.0);
  float tilt = exp(-depth / reach);

  vec2 grad = sdf.gb * 2.0 - 1.0;
  float gradLen = length(grad);
  vec2 outward = gradLen > 1e-4 ? -grad / gradLen : vec2(0.0);

  float lateral = tilt * clamp(gradLen, 0.0, 1.0);
  vec3 normal = vec3(outward * lateral, sqrt(max(1.0 - lateral * lateral, 0.0)));

  vec3 refl = reflect(vec3(0.0, 0.0, -1.0), normal);
  float v = fieldAt(uv + refl.xy * u_reflection, t);

  float contourReach = reach * 0.4;
  float rim = 1.0 - smoothstep(0.0, contourReach, depth);
  v = mix(v, 1.0, rim * rim * clamp(gradLen, 0.0, 1.0) * u_contourStrength);

  vec3 color = palette(v);
  color = fitGamut(color);
  color = toGamma(color);
  gl_FragColor = vec4(color, 1.0);
}
