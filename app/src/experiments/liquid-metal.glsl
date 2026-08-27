/**
 * Liquid Metal in Forms — a Pencil-compatible 2D interpretation of Sabo
 * Sugi's Three.js study: https://codepen.io/sabosugi/pen/yyabKEP
 *
 * The reference's simplex domain warping, shape-aware inflation, metallic
 * environment, and iridescent thickness variation are rebuilt here as a
 * single fragment shader. The original CodePen is Copyright (c) 2026 Sabo
 * Sugi and published under the MIT License.
 *
 * The host SDF is deliberately optional. A populated field adds contour
 * relief and the host clips the fill to its silhouette; an empty Rectangle
 * field (or Shape = None in the workbench) renders the same liquid material
 * across the full quad. Visibility never depends on the SDF.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @sdf */
uniform sampler2D u_shape;

// SECTION: Fluid Dynamics
/**
 * Size of the broad liquid ripples. Lower values make larger, calmer waves.
 * @label Ripple Scale
 * @default 3
 * @range 0.25, 12
 */
uniform float u_scale;

/**
 * Strength of the domain warp that folds the noise into liquid swirls.
 * @label Warp
 * @default 1.5
 * @range 0, 4
 */
uniform float u_warp;

/**
 * Strength of the ripples in the reconstructed surface normal.
 * @label Distortion
 * @default 1.5
 * @range 0, 5
 */
uniform float u_distortion;

/**
 * Drift speed of the liquid. Negative values reverse the flow.
 * @label Speed
 * @default 0.18
 * @range -2, 2
 */
uniform float u_speed;

/**
 * Screen direction the liquid drifts toward, in degrees.
 * @label Flow Angle
 * @default 90
 * @range 0, 360
 */
uniform float u_flowAngle;

// SECTION: Shape
/**
 * How strongly a populated host SDF inflates the material along its contour.
 * Set to 0 for the same liquid surface inside every silhouette.
 * @label Shape Reactivity
 * @default 1
 * @range 0, 5
 */
uniform float u_shapeReactivity;

/**
 * Width of the rounded contour transition, in canvas pixels.
 * @label Contour Width
 * @default 72
 * @range 2, 240
 */
uniform float u_contourWidth;

/**
 * Keeps turbulent ripples away from a populated shape's outline. Has no
 * effect when the SDF is empty.
 * @label Edge Protection
 * @default 0.8
 * @range 0, 1
 */
uniform float u_edgeProtection;

// SECTION: Material
/**
 * Base color of the metal.
 * @label Tint
 * @color
 * @default #eeeeee
 */
uniform vec3 u_tint;

/**
 * Blend from diffuse pearlescent material to reflected metal.
 * @label Metalness
 * @default 0.82
 * @range 0, 1
 */
uniform float u_metalness;

/**
 * Softens the reflected horizon and studio bands.
 * @label Roughness
 * @default 0.28
 * @range 0, 1
 */
uniform float u_roughness;

/**
 * Strength of the tight clearcoat highlight.
 * @label Clearcoat
 * @default 0.35
 * @range 0, 1
 */
uniform float u_clearcoat;

/**
 * Overall brightness before the highlight rolloff.
 * @label Exposure
 * @default 1.15
 * @range 0.2, 3
 */
uniform float u_exposure;

// SECTION: Iridescence
/**
 * Amount of thin-film rainbow color at glancing angles.
 * @label Intensity
 * @default 0.9
 * @range 0, 1
 */
uniform float u_iridescence;

/**
 * Optical density of the thin film; higher values spread the hues farther.
 * @label Index of Refraction
 * @default 1.45
 * @range 1, 3
 */
uniform float u_ior;

/**
 * Mean thin-film thickness used to choose the reflected hue.
 * @label Thickness
 * @default 780
 * @range 0, 1500
 */
uniform float u_thickness;

/**
 * How much the ripple field varies thin-film thickness across the surface.
 * @label Thickness Variation
 * @default 180
 * @range 0, 800
 */
uniform float u_thicknessVariation;

// SECTION: Environment
/**
 * Direction of the bright studio hemisphere and key light, in degrees.
 * @label Light Angle
 * @default 115
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * Sharpness of the light/dark studio horizon reflected in the metal.
 * @label Horizon
 * @default 0.72
 * @range 0, 1
 */
uniform float u_horizon;

/**
 * Number of vertical softbox reflections around the environment.
 * @label Softboxes
 * @default 3
 * @range 0, 12
 */
uniform float u_stripes;

/**
 * Width of each reflected softbox.
 * @label Softbox Width
 * @default 0.28
 * @range 0.05, 0.9
 */
uniform float u_stripeWidth;

/**
 * Shift between the dark ground and bright sky reflected on flat areas.
 * @label View Tilt
 * @default 0.08
 * @range -1, 1
 */
uniform float u_tilt;

vec4 permute(vec4 x) {
  return mod(((x * 34.0) + 1.0) * x, 289.0);
}

vec4 taylorInvSqrt(vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

// Ashima Arts simplex noise, as used by the reference material.
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

float studioStripe(float phase, float width, float roughness) {
  float local = abs(fract(phase) - 0.5);
  float halfWidth = clamp(width * 0.5, 0.025, 0.45);
  float feather = mix(0.015, 0.16, roughness);
  return 1.0 - smoothstep(halfWidth, min(0.499, halfWidth + feather), local);
}

vec3 filmColor(float phase) {
  vec3 wave = 0.5 + 0.5 * cos(6.2831853 * (phase + vec3(0.00, 0.33, 0.67)));
  return mix(vec3(0.72), wave, 0.78);
}

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float aspect = u_resolution.x / u_resolution.y;
  vec2 q = (uv - 0.5) * vec2(aspect, 1.0);

  float flowRad = radians(u_flowAngle);
  vec2 flow = vec2(cos(flowRad), sin(flowRad)) * u_time * u_speed;
  vec3 p = vec3((q + flow * 0.12) * u_scale, u_time * u_speed * 0.16);

  vec3 warp = vec3(
    snoise(p + vec3(0.0, 0.0, u_time * 0.10)),
    snoise(p + vec3(114.5, 22.1, u_time * 0.08)),
    snoise(p + vec3(233.2, 51.5, -u_time * 0.07))
  );
  vec3 warpedP = p + warp * u_warp;
  float eps = 0.035;
  float fluid = snoise(warpedP);
  float nx = snoise(warpedP + vec3(eps, 0.0, 0.0));
  float ny = snoise(warpedP + vec3(0.0, eps, 0.0));
  vec2 fluidGrad = vec2(nx - fluid, ny - fluid) / eps;

  // An empty @sdf (plain Rectangle / no host shape) contributes no contour,
  // while the liquid normal remains fully active across the canvas.
  vec4 field = texture2D(u_shape, uv);
  float d = max(field.r, 0.0);
  float shaped = step(0.0001, d);
  vec2 shapeGrad = field.gb;
  float shapeGradLen = length(shapeGrad);
  vec2 shapeDir = shapeGradLen > 0.00001 ? shapeGrad / shapeGradLen : vec2(0.0);
  float contourWidth = max(u_contourWidth, 1.0);
  float edgeDepth = exp(-d / contourWidth) * shaped;
  float protectedNoise = mix(
    1.0,
    smoothstep(0.0, contourWidth, d),
    u_edgeProtection * shaped
  );

  vec2 heightGrad = fluidGrad * u_distortion * 0.32 * protectedNoise;
  heightGrad += shapeDir * edgeDepth * u_shapeReactivity * 1.8;
  vec3 n = normalize(vec3(-heightGrad, 1.0));

  vec3 view = normalize(vec3(-q * 0.28, 1.0));
  vec3 refl = 2.0 * dot(n, view) * n - view;

  float lightRad = radians(u_lightAngle - 90.0);
  float lc = cos(lightRad);
  float ls = sin(lightRad);
  vec2 reflectedUp = vec2(
    lc * refl.x + ls * refl.y,
    -ls * refl.x + lc * refl.y
  );
  float elev = reflectedUp.y + u_tilt;
  float azim = atan(reflectedUp.x, refl.z + 0.0001);

  float rough = clamp(u_roughness, 0.0, 1.0);
  float horizonSoft = max(mix(0.48, 0.035, u_horizon), rough * 0.35);
  float horizon = smoothstep(-horizonSoft, horizonSoft, elev);
  float ground = mix(0.035, 0.24, clamp(-elev, 0.0, 1.0));
  float sky = mix(0.96, 0.52, clamp(elev, 0.0, 1.0));
  float env = mix(ground, sky, horizon);

  float stripePhase = azim * max(u_stripes, 0.0) * 0.15915494;
  float stripeOn = step(0.001, u_stripes);
  float stripe = studioStripe(stripePhase, u_stripeWidth, rough);
  env += stripe * stripeOn * horizon * mix(0.75, 0.28, rough);
  env = mix(env, 0.48, rough * 0.55);

  float fresnel = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
  float filmPhase = u_thickness * 0.0017
    + fluid * u_thicknessVariation * 0.0025
    + fresnel * (u_ior - 1.0) * 1.8;
  vec3 iri = filmColor(filmPhase);
  float iriAmount = u_iridescence * clamp(0.18 + fresnel * 1.15, 0.0, 1.0);

  vec3 diffuse = u_tint * (0.32 + 0.5 * max(n.z, 0.0));
  vec3 metal = u_tint * env;
  vec3 col = mix(diffuse, metal, u_metalness);
  col = mix(col, col * iri * 1.35, iriAmount);

  vec3 lightDir = normalize(vec3(cos(radians(u_lightAngle)), sin(radians(u_lightAngle)), 0.8));
  vec3 halfDir = normalize(lightDir + view);
  float glossPower = mix(110.0, 10.0, rough);
  float clearcoat = pow(max(dot(n, halfDir), 0.0), glossPower) * u_clearcoat;
  col += vec3(clearcoat);
  col += u_tint * fresnel * 0.18;
  col *= u_exposure;

  // Filmic shoulder and subtle dithering keep the broad chrome gradients clean.
  vec3 hi = max(col - 0.72, 0.0);
  col = min(col, vec3(0.72)) + hi / (1.0 + 1.8 * hi);
  col += (hash21(gl_FragCoord.xy) - 0.5) * 0.006;
  col = clamp(col, 0.0, 1.0);

  // Always opaque here. The host clips populated shapes; an empty SDF remains
  // a valid full-quad liquid material instead of disappearing.
  gl_FragColor = vec4(col, 1.0);
}
