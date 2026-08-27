/**
 * Liquid Metal in Forms — a Pencil-compatible port of Sabo Sugi's Three.js
 * study: https://codepen.io/sabosugi/pen/yyabKEP
 *
 * This follows the source material injection directly: the same simplex-noise
 * function, fixed 1.5 domain warp, 0.03 finite-difference epsilon, normalized
 * 3D noise normal, blurred shape-mask inflation, contour flow, edge protection,
 * physical-material defaults, and thin-film thickness range. The only replaced
 * part is Three.js's RoomEnvironment/PBR renderer, represented here by a small
 * neutral room-light approximation so the shader stays standalone in Pencil.
 *
 * Copyright (c) 2026 Sabo Sugi. Original CodePen published under the MIT
 * License. Adaptation retains this notice under the same license.
 *
 * The SDF remains optional: a populated field supplies the form's bevel and
 * mask reactivity, while Pencil's empty Rectangle field renders the identical
 * material over the full quad. Visibility never depends on the SDF.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @sdf */
uniform sampler2D u_shape;

// SECTION: Fluid Dynamics
/**
 * Exact spatial scale from the source material. Its local SVG coordinates are
 * reproduced below in a 100-unit canvas.
 * @label Ripple Scale
 * @default 0.00298
 * @range 0.0001, 0.015
 */
uniform float u_scale;

/**
 * Amount that a blurred host-shape mask offsets the noise in depth.
 * @label Shape Reactivity
 * @default 1
 * @range 0, 5
 */
uniform float u_shapeReactivity;

/**
 * Strength of the normalized simplex-noise normal added to the base surface.
 * @label Distortion
 * @default 1.52
 * @range 0, 5
 */
uniform float u_distortion;

/**
 * Protects beveled side faces from fluid-normal distortion.
 * @label Edge Sharpness
 * @default 1
 * @range 0, 1
 */
uniform float u_edgeProtection;

/**
 * Contour-flow speed. The source initializes this to 0, producing a static
 * material until motion is deliberately enabled.
 * @label Speed
 * @default 0
 * @range -2, 2
 */
uniform float u_speed;

// SECTION: Iridescence (Rainbow)
/**
 * Thin-film iridescence intensity.
 * @label Intensity
 * @default 0.907
 * @range 0, 1
 */
uniform float u_iridescence;

/**
 * Thin-film index of refraction.
 * @label Index of Refraction
 * @default 1
 * @range 1, 3
 */
uniform float u_iridescenceIOR;

/**
 * Lower end of the iridescence thickness range.
 * @label Thickness Min
 * @default 759
 * @range 0, 1500
 */
uniform float u_thicknessMin;

/**
 * Upper end of the iridescence thickness range.
 * @label Thickness Max
 * @default 800
 * @range 0, 1500
 */
uniform float u_thicknessMax;

// SECTION: Base Material
/**
 * Physical-material roughness.
 * @label Roughness
 * @default 0.452
 * @range 0, 1
 */
uniform float u_roughness;

/**
 * Physical-material metalness.
 * @label Metalness
 * @default 0.587
 * @range 0, 1
 */
uniform float u_metalness;

/**
 * Physical-material clearcoat amount.
 * @label Clearcoat
 * @default 0.071
 * @range 0, 1
 */
uniform float u_clearcoat;

vec4 permute(vec4 x) {
  return mod(((x * 34.0) + 1.0) * x, 289.0);
}

vec4 taylorInvSqrt(vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

// The reference's GLSL simplex3D function, unchanged apart from formatting.
float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);
  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;
  i = mod(i, 289.0);
  vec4 p = permute(permute(permute(
    i.z + vec4(0.0, i1.z, i2.z, 1.0)
  ) + i.y + vec4(0.0, i1.y, i2.y, 1.0)) + i.x + vec4(0.0, i1.x, i2.x, 1.0));
  float n_ = 1.0 / 7.0;
  vec3 ns = n_ * D.wyz - D.xzx;
  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);
  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);
  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));
  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);
  vec4 norm = taylorInvSqrt(vec4(
    dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)
  ));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;
  vec4 m = max(0.6 - vec4(
    dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)
  ), 0.0);
  m *= m;
  return 42.0 * dot(m * m, vec4(
    dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)
  ));
}

float softBand(float x, float center, float halfWidth, float softness) {
  return 1.0 - smoothstep(halfWidth, halfWidth + softness, abs(x - center));
}

/** Neutral approximation of Three.js RoomEnvironment for a standalone fill. */
vec3 roomEnvironment(vec3 r, float roughness) {
  float vertical = smoothstep(-0.65, 0.75, r.y);
  vec3 env = mix(vec3(0.16, 0.17, 0.18), vec3(0.92, 0.93, 0.94), vertical);

  float wall = 1.0 - smoothstep(0.35, 0.95, abs(r.x));
  env += vec3(0.34) * wall * smoothstep(-0.35, 0.55, r.y);

  float leftPanel = softBand(r.x, -0.48, 0.16, 0.18)
    * softBand(r.y, 0.18, 0.52, 0.2);
  float topPanel = softBand(r.y, 0.72, 0.14, 0.2);
  env += vec3(0.72, 0.70, 0.67) * leftPanel;
  env += vec3(0.48) * topPanel;

  float darkPanel = softBand(r.x + r.y * 0.45, 0.22, 0.22, 0.26)
    * smoothstep(-0.45, 0.35, -r.y);
  env *= 1.0 - darkPanel * 0.72;

  return mix(env, vec3(0.72), roughness * 0.62);
}

vec3 thinFilm(float thickness, float ior) {
  float optical = thickness * max(ior, 1.0) * 0.0125;
  vec3 phase = optical * vec3(1.00, 1.17, 1.36);
  return 0.72 + 0.28 * cos(phase + vec3(0.0, 2.1, 4.2));
}

vec3 acesToneMap(vec3 x) {
  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;
  vec2 localPos = (uv - 0.5) * vec2(aspect, 1.0) * 100.0;

  vec4 field = texture2D(u_shape, uv);
  float shapeDistance = max(field.r, 0.0);
  float shaped = step(0.0001, shapeDistance);
  float gradLength = length(field.gb);
  vec2 shapeDirection = gradLength > 0.00001 ? field.gb / gradLength : vec2(0.0);

  // CodePen rasterizes the SVG into a 1024px mask with blur(45px). This SDF
  // ramp is its resolution-independent equivalent inside the selected form.
  float smoothDist = smoothstep(0.0, 45.0, shapeDistance) * shaped;
  vec2 maskGrad = shapeDirection * (1.0 - smoothDist) * shaped;

  vec3 p = vec3(localPos * u_scale, 0.0);
  p.z += smoothDist * u_shapeReactivity * 150.0 * u_scale;

  vec2 contourTangent = vec2(-maskGrad.y, maskGrad.x);
  p.xy += contourTangent * (u_time * u_speed * 0.5);
  p.y -= u_time * u_speed * 0.1;

  vec3 warp;
  warp.x = snoise(p + vec3(0.0, 0.0, u_time * 0.1));
  warp.y = snoise(p + vec3(114.5, 22.1, u_time * 0.1));
  warp.z = snoise(p + vec3(233.2, 51.5, u_time * 0.1));
  vec3 warpedP = p + warp * 1.5;

  float eps = 0.03;
  float n0 = snoise(warpedP);
  float nx = snoise(warpedP + vec3(eps, 0.0, 0.0));
  float ny = snoise(warpedP + vec3(0.0, eps, 0.0));
  float nz = snoise(warpedP + vec3(0.0, 0.0, eps));
  vec3 noiseNormal = normalize(vec3(nx - n0, ny - n0, nz - n0));

  // Reconstruct the fixed extruded/beveled base geometry that Three.js supplies
  // before the source adds its fluid normal. Empty SDFs use a flat face.
  float bevelT = clamp(shapeDistance / 30.0, 0.0, 1.0);
  float bevelSlope = shaped * (1.0 - bevelT) * 2.4;
  vec3 originalNormal = normalize(vec3(-shapeDirection * bevelSlope, 1.0));

  float isFlatFace = smoothstep(0.1, 0.9, abs(originalNormal.z));
  float edgeMask = mix(1.0, isFlatFace, u_edgeProtection);
  vec3 normal = normalize(originalNormal + noiseNormal * u_distortion * edgeMask);

  vec3 view = vec3(0.0, 0.0, 1.0);
  vec3 reflected = 2.0 * dot(normal, view) * normal - view;
  float roughness = clamp(u_roughness, 0.0, 1.0);
  vec3 env = roomEnvironment(reflected, roughness);

  vec3 baseColor = vec3(0.9333333);
  float diffuseLight = 0.42
    + 0.58 * max(dot(normal, normalize(vec3(0.45, 0.72, 0.9))), 0.0);
  vec3 diffuse = baseColor * diffuseLight;
  vec3 color = mix(diffuse, baseColor * env, u_metalness);

  float fresnel = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 5.0);
  float fluidNoise = n0 + smoothDist * u_shapeReactivity * 2.0;
  float thicknessMix = clamp(fluidNoise * 0.5 + 0.5, 0.0, 1.0);
  float thickness = mix(u_thicknessMin, u_thicknessMax, thicknessMix);
  vec3 film = thinFilm(thickness, u_iridescenceIOR);
  float filmAmount = u_iridescence * (0.025 + fresnel * 0.28);
  color = mix(color, color * film, filmAmount);

  vec3 key = normalize(vec3(0.42, 0.72, 0.78));
  vec3 halfVector = normalize(key + view);
  float specPower = mix(180.0, 12.0, roughness);
  float specular = pow(max(dot(normal, halfVector), 0.0), specPower);
  color += vec3(specular * (0.18 + u_clearcoat * 0.82));
  color += vec3(fresnel * u_clearcoat * 0.24);

  // CodePen: ACESFilmicToneMapping with exposure 1.3 and material dithering.
  color = acesToneMap(max(color, 0.0) * 1.3);
  color += (hash21(gl_FragCoord.xy) - 0.5) * 0.004;
  color = clamp(color, 0.0, 1.0);

  // The host performs silhouette clipping. Empty SDFs remain full-quad.
  gl_FragColor = vec4(color, 1.0);
}
