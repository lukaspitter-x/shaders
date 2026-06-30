/** @resolution */
uniform vec2 u_resolution;

/** @sdf */
uniform sampler2D u_shape;

/**
 * Color of the light scattering through the material.
 * @label Light Color
 * @color
 * @default #f4da26
 */
uniform vec3 u_color;

/**
 * Direction the light enters from, in degrees.
 * @label Light Angle
 * @default 72
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * How deep light penetrates before being absorbed, as a fraction of height.
 * @label Light Depth
 * @default 0.11
 * @range 0.02, 0.4
 */
uniform float u_scatter;

/**
 * Absorption density of the medium. Higher values absorb light faster, so the
 * glow stays near the lit surface and shifts color more strongly with depth.
 * @label Density
 * @default 3
 * @range 0.5, 10
 */
uniform float u_density;

/**
 * Ambient light entering from all edges, filling the shape with a soft base
 * glow independent of the key light direction.
 * @label Ambient Glow
 * @default 0.2
 * @range 0, 1
 */
uniform float u_ambient;

/**
 * Angular spread of the light, in degrees. Wider softens the directional
 * shadow so corners don't produce a hard diagonal crease.
 * @label Softness
 * @default 16
 * @range 0, 45
 */
uniform float u_softness;

/**
 * Amount of soft organic cloud variation in the medium's density.
 * @label Cloud Amount
 * @default 0.25
 * @range 0, 1
 */
uniform float u_noise;

/**
 * Scale of the cloud noise. Higher is finer.
 * @label Cloud Scale
 * @default 2
 * @range 0.2, 8
 */
uniform float u_noiseScale;

vec3 toLinear(vec3 c) {
  return pow(c, vec3(2.2));
}

vec3 toGamma(vec3 c) {
  return pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2));
}

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec2 mod289(vec2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}
vec3 permute(vec3 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
      -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod289(i);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amp = 0.5;
  float norm = 0.0;
  for (int i = 0; i < 5; i++) {
    sum += amp * snoise(p);
    norm += amp;
    p = p * 2.0 + 19.0;
    amp *= 0.5;
  }
  return sum / norm;
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

float lightThickness(vec2 fragPos, vec2 L) {
  float t = 0.0;
  for (int i = 0; i < 160; i++) {
    vec2 p = (fragPos + L * t) / u_resolution;
    if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
      break;
    }
    float r = texture2D(u_shape, p).r;
    if (r <= 0.0) {
      break;
    }
    t += max(r, 1.0);
  }
  return t;
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;

  vec4 sdf = sdfBicubic(uv, vec2(textureSize(u_shape, 0)));
  float depth = sdf.r;

  if (depth <= 0.0) {
    gl_FragColor = vec4(0.0);
    return;
  }

  float penetration = max(u_scatter * min(u_resolution.x, u_resolution.y), 1.0);

  float aspect = u_resolution.x / u_resolution.y;
  vec2 np = (uv - 0.5) * vec2(aspect, 1.0) * u_noiseScale;
  float clouds = fbm(np);
  penetration *= clamp(1.0 + u_noise * clouds, 0.2, 3.0);

  vec3 colorLin = toLinear(u_color);
  vec3 absorb = u_density * (vec3(1.0) - colorLin);

  vec2 Lc = vec2(cos(radians(u_lightAngle)), sin(radians(u_lightAngle)));
  float k = clamp(log(0.5) / log(max(cos(radians(u_softness)), 1e-4)), 1.0, 400.0);

  float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  const int N = 20;
  vec3 keyAcc = vec3(0.0);
  vec3 ambAcc = vec3(0.0);
  float keyW = 0.0;
  for (int i = 0; i < N; i++) {
    float a = (float(i) + ign) / float(N) * 6.2831853;
    vec2 dir = vec2(cos(a), sin(a));
    vec3 ti = exp(-absorb * (lightThickness(gl_FragCoord.xy, dir) / penetration));
    ambAcc += ti;
    float w = pow(max(dot(dir, Lc), 0.0), k);
    keyAcc += ti * w;
    keyW += w;
  }
  vec3 color = colorLin * (keyAcc / max(keyW, 1e-4) + u_ambient * ambAcc / float(N));

  float edgeFade = smoothstep(0.0, 1.5, depth);
  gl_FragColor = vec4(toGamma(color), edgeFade);
}
