/**
 * Chrome — beveled metal / liquid-chrome relief for any host shape.
 *
 * Treats the host layer's SDF as a height field: the signed distance drives a
 * bevel/dome profile, the profile's finite-difference gradient gives a surface
 * normal, and the normal indexes a procedural "studio" environment (horizon
 * band + softbox stripes) with an optional image environment blended on top.
 * Straight-on view; presets cover brushed metal, polished chrome, animated
 * liquid chrome, and thin rim chrome.
 */

/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @sdf */
uniform sampler2D u_shape;

// SECTION: Shape
/**
 * Height of the fake extrusion, in canvas pixels.
 * @label Depth
 * @default 22
 * @range 1, 80
 */
uniform float u_depth;

/**
 * Width of the bevel ramp from the outline to the flat top, in canvas pixels.
 * Larger than the shape's half-width turns the whole surface into a dome.
 * @label Bevel Width
 * @default 90
 * @range 2, 200
 */
uniform float u_bevel;

/**
 * Bevel cross-section: 0 = straight chamfer, 1 = round (quarter-circle) dome.
 * @label Profile
 * @default 1
 * @range 0, 1
 */
uniform float u_profile;

/**
 * Rounds the junction where the bevel meets the flat top. 0 keeps a hard
 * machined crease; higher melts the bevel smoothly into the plateau.
 * @label Shoulder
 * @default 0.2
 * @range 0, 0.5
 */
uniform float u_shoulder;

// SECTION: Material
/**
 * Metal tint multiplied over the reflected environment.
 * @label Tint
 * @color
 * @default #ffffff
 */
uniform vec3 u_tint;

/**
 * Micro-roughness: blurs the environment toward an even satin sheen.
 * @label Roughness
 * @default 0.05
 * @range 0, 1
 */
uniform float u_rough;

/**
 * Contrast of the reflected environment around mid gray.
 * @label Contrast
 * @default 1.35
 * @range 0.2, 2.5
 */
uniform float u_contrast;

/**
 * Extra brightness on grazing edges (fresnel rim).
 * @label Edge Shine
 * @default 1.1
 * @range 0, 2
 */
uniform float u_fresnel;

/**
 * Brushed-metal streaks across flat areas.
 * @label Brush Streaks
 * @default 0
 * @range 0, 1
 */
uniform float u_brush;

/**
 * Fineness of the brush streaks. Higher is finer.
 * @label Brush Fineness
 * @default 4
 * @range 1, 10
 */
uniform float u_brushScale;

// SECTION: Flow
/**
 * Liquid-metal stripe layer blended over the reflection: repeating chrome
 * bands that follow the shape's contours and drift over time. 0 disables.
 * @label Flow Amount
 * @default 0
 * @range 0, 1
 */
uniform float u_flow;

/**
 * Density of the stripe pattern.
 * @label Repetition
 * @default 4
 * @range 1, 12
 */
uniform float u_flowRep;

/**
 * Screen direction the stripes run across, degrees.
 * @label Flow Angle
 * @default 70
 * @range 0, 360
 */
uniform float u_flowAngle;

/**
 * Drift speed of the stripes, in cycles per second. Negative reverses.
 * @label Flow Speed
 * @default 0.3
 * @range -2, 2
 */
uniform float u_flowSpeed;

/**
 * 0 = straight stripes across the canvas, 1 = stripes wrap along the
 * shape's outline (contour-following, via the SDF).
 * @label Contour Follow
 * @default 0.7
 * @range 0, 1
 */
uniform float u_flowContour;

/**
 * Noise warp of the stripes for an organic, molten look.
 * @label Flow Distortion
 * @default 0.4
 * @range 0, 2
 */
uniform float u_flowDistort;

/**
 * Softness of the stripe transitions. 0 is hard-edged chrome bands.
 * @label Flow Softness
 * @default 0.3
 * @range 0, 1
 */
uniform float u_flowSoft;

/**
 * Chromatic dispersion: offsets the red/blue stripe phases for subtle
 * rainbow fringing on the band edges.
 * @label Dispersion
 * @default 0.2
 * @range 0, 1
 */
uniform float u_flowShift;

// SECTION: Environment
/**
 * Screen direction the environment's "up" (and key light) comes from, degrees.
 * @label Light Angle
 * @default 90
 * @range 0, 360
 */
uniform float u_lightAngle;

/**
 * Sharpness of the sky/ground horizon line — the classic chrome divide.
 * @label Horizon
 * @default 0.75
 * @range 0, 1
 */
uniform float u_horizon;

/**
 * Number of softbox stripes around the environment.
 * @label Stripes
 * @default 2
 * @range 0, 16
 */
uniform float u_stripeFreq;

/**
 * Brightness of the softbox stripes.
 * @label Stripe Strength
 * @default 0.45
 * @range 0, 1
 */
uniform float u_stripeAmt;

/**
 * Shifts what flat surfaces reflect: negative shows the dark ground (gunmetal
 * plates), positive the bright sky. 0 leaves flat tops exactly on the horizon.
 * @label View Tilt
 * @default 0.2
 * @range -1, 1
 */
uniform float u_tilt;

/**
 * Virtual-camera perspective. 0 is a flat orthographic mirror; higher sweeps
 * the environment across flat faces (the diagonal streaks of chrome plates).
 * @label Perspective
 * @default 0.35
 * @range 0, 1
 */
uniform float u_persp;

// SECTION: Image Environment
/**
 * Optional environment image reflected by the surface (sphere-mapped).
 * @label Env Image
 * @assets env
 */
uniform sampler2D u_env;

/**
 * Blend between the procedural studio and the environment image.
 * @label Env Image Mix
 * @default 0
 * @range 0, 1
 */
uniform float u_envMix;

/**
 * Zoom of the environment image reflection.
 * @label Env Zoom
 * @default 1
 * @range 0.3, 3
 */
uniform float u_envZoom;

// SECTION: Motion
/**
 * Spin of the environment around the vertical axis, degrees. The static
 * starting angle that Env Spin animates from.
 * @label Env Rotation
 * @default 0
 * @range 0, 360
 */
uniform float u_envRotation;

/**
 * Continuous environment rotation, degrees per second. Negative reverses
 * direction; 0 is static.
 * @label Env Spin
 * @default 0
 * @range -90, 90
 */
uniform float u_sweep;

/**
 * Continuous rotation of the light/env-up direction, degrees per second.
 * Negative reverses direction; 0 is static.
 * @label Light Spin
 * @default 0
 * @range -90, 90
 */
uniform float u_lightSpin;

/**
 * Animated liquid swell of the surface. 0 keeps the metal rigid.
 * @label Liquid Wobble
 * @default 0
 * @range 0, 1
 */
uniform float u_wobble;

/**
 * Spatial scale of the liquid swell. Higher is choppier.
 * @label Wobble Scale
 * @default 2.5
 * @range 0.5, 8
 */
uniform float u_wobbleScale;

/**
 * Speed of the liquid swell.
 * @label Wobble Speed
 * @default 0.8
 * @range 0, 3
 */
uniform float u_wobbleSpeed;

/**
 * Screen direction the liquid swell drifts toward, degrees.
 * @label Wobble Direction
 * @default 0
 * @range 0, 360
 */
uniform float u_wobbleDir;

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One cycle of a chrome stripe ramp (paper-design style): a thin bright
// strip, a dark gap, a small bright echo, then a wide dark-to-bright sweep.
float chromeRamp(float t, float blur) {
  float c = mix(0.95, 0.08, smoothstep(0.10, 0.10 + blur, t));
  c = mix(c, 0.75, smoothstep(0.16, 0.16 + blur, t));
  c = mix(c, 0.12, smoothstep(0.22, 0.22 + blur, t));
  c = mix(c, mix(0.12, 0.95, smoothstep(0.28, 1.0, t)), smoothstep(0.28, 0.28 + blur, t));
  return c;
}

/** Liquid swell field and its analytic gradient (in p units). */
void wobble(vec2 p, out float w, out vec2 grad) {
  float t = u_time * u_wobbleSpeed;
  // Rotate the field so the drift direction is dialable; the gradient comes
  // back through the transpose rotation.
  float wa = radians(u_wobbleDir);
  float wc = cos(wa);
  float ws = sin(wa);
  vec2 pr = vec2(wc * p.x + ws * p.y, -ws * p.x + wc * p.y);
  vec2 q = pr * u_wobbleScale;
  float inner1 = q.y * 2.3 - t * 1.3;
  float inner2 = q.x * 1.9 + t * 0.8;
  float A = q.x * 3.1 + t * 1.7 + sin(inner1);
  float B = q.y * 2.7 - t + sin(inner2);
  w = (sin(A) + sin(B)) * 0.25;
  vec2 gq = 0.25 * (cos(A) * vec2(3.1, 2.3 * cos(inner1)) + cos(B) * vec2(1.9 * cos(inner2), 2.7));
  vec2 gpr = gq * u_wobbleScale;
  grad = vec2(wc * gpr.x - ws * gpr.y, ws * gpr.x + wc * gpr.y);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec4 field = texture2D(u_shape, uv);
  float d = field.r;
  if (d <= 0.0) {
    gl_FragColor = vec4(0.0);
    return;
  }

  // Surface normal, fully analytic: the @sdf texture's gb channels carry the
  // distance-field gradient (per Pencil's contract — never differentiate the
  // r channel numerically). A true SDF has |∇d| = 1, so only the direction
  // is needed; the height slope comes from the chain rule h'(d)·∇d plus the
  // wobble field's own analytic gradient.
  vec2 g = field.gb;
  float glen = length(g);
  vec2 gdir = glen > 1e-5 ? g / glen : vec2(0.0);

  float aspect = u_resolution.x / u_resolution.y;
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

  float bevel = max(u_bevel, 1.0);
  float t01 = clamp(d / bevel, 0.0, 1.0);
  float dome = sqrt(max(1.0 - (1.0 - t01) * (1.0 - t01), 0.0));
  float domeD = (1.0 - t01) / max(dome, 0.02);
  float hD = mix(1.0, domeD, u_profile);
  float dtdd = (t01 > 0.0 && t01 < 1.0) ? 1.0 / bevel : 0.0;

  // C1 shoulder: within u_shoulder of the plateau height, ease the profile
  // slope quadratically to zero so the bevel blends into the flat top with
  // no crease (a chamfer otherwise arrives still climbing).
  float h01 = mix(t01, dome, u_profile);
  float un = 1.0 - h01;
  if (u_shoulder > 0.001 && un < u_shoulder) hD *= un / u_shoulder;

  float w;
  vec2 wgradP;
  wobble(p, w, wgradP);
  vec2 wgradPx = wgradP / u_resolution.y;

  vec2 gradH = u_depth *
    ((hD + 0.35 * u_wobble * w) * dtdd * gdir + 0.35 * u_wobble * t01 * wgradPx);
  vec3 n = normalize(vec3(-gradH, 1.0));

  // View ray from a virtual camera above the canvas center; u_persp = 0
  // degenerates to the straight-on orthographic view.
  vec2 vxy = p * u_persp;
  vec3 v = normalize(vec3(-vxy, 1.0));
  vec3 r = 2.0 * dot(n, v) * n - v;

  // Rotate screen space so the environment's "up" follows the light angle
  // (animatable via Light Spin).
  float lightAng = u_lightAngle + u_time * u_lightSpin;
  float envUp = radians(lightAng - 90.0);
  float cu = cos(envUp);
  float su = sin(envUp);
  vec2 rr = vec2(cu * r.x + su * r.y, -su * r.x + cu * r.y);

  float rot = radians(u_envRotation) + u_time * radians(u_sweep);
  float azim = atan(rr.x, r.z + 1e-4) + rot;
  float elev = rr.y + u_tilt;

  // Procedural studio: bright band above a horizon, dark falloff below.
  float rough = clamp(u_rough, 0.0, 1.0);
  float soft = mix(0.5, 0.035, u_horizon);
  soft = max(soft, rough * 0.45);
  float horizon = smoothstep(-soft, soft, elev);
  float sky = mix(0.85, 0.5, clamp(elev, 0.0, 1.0));
  float ground = mix(0.04, 0.28, clamp(-elev, 0.0, 1.0));
  float envL = mix(ground, sky, horizon);

  // Softbox stripes around the azimuth — bipolar, so bright bars sit between
  // darker gaps and the sky keeps structure instead of washing to white.
  float bars = 0.5 + 0.5 * cos(azim * u_stripeFreq);
  bars = pow(bars, mix(6.0, 1.2, rough));
  envL += u_stripeAmt * (bars - 0.35) * horizon * 0.9;

  envL = mix(envL, 0.42, rough * 0.6);

  // Steep slopes reflect back toward the viewer — a dark room, not the sky.
  float back = clamp(-r.z, 0.0, 1.0);
  envL = mix(envL, 0.15, back * back * 0.85);

  // Brushed streaks on near-flat areas, drawn across the light direction.
  float topMask = smoothstep(0.85, 0.98, n.z);
  float la = radians(lightAng);
  vec2 dir = vec2(cos(la), sin(la));
  vec2 perp = vec2(-dir.y, dir.x);
  vec2 sp = gl_FragCoord.xy;
  float streak = vnoise(vec2(dot(sp, perp) * u_brushScale * 0.01, dot(sp, dir) * 0.002));
  envL *= 1.0 + u_brush * topMask * (streak - 0.5) * 0.8;

  envL = clamp(0.45 + (envL - 0.45) * u_contrast, 0.0, 1.6);

  vec3 envC = vec3(envL);
  if (u_envMix > 0.001) {
    // Sphere-map the reflection vector into the env image, rotated + zoomed.
    vec2 rxy = rr / max(u_envZoom, 0.05);
    float m = 2.0 * sqrt(rxy.x * rxy.x + rxy.y * rxy.y + (r.z + 1.0) * (r.z + 1.0));
    vec2 suv = rxy / max(m, 1e-4) + 0.5;
    suv.x = fract(suv.x + rot * 0.15915494);
    suv.y = 1.0 - suv.y;
    vec3 img = texture2D(u_env, suv).rgb;
    envC = mix(envC, img * (0.4 + 0.8 * envL), u_envMix);
  }

  // Liquid-metal flow stripes (paper-design style): a repeating chrome ramp
  // indexed by a coordinate that blends a screen direction with the SDF
  // distance (contour-following), noise-warped and drifting over time.
  if (u_flow > 0.001) {
    float fa = radians(u_flowAngle);
    vec2 fdir = vec2(cos(fa), sin(fa));
    vec2 fp = (uv - 0.5) * vec2(aspect, 1.0);
    float dNorm = d / u_resolution.y;
    float phase = mix(dot(fp, fdir), -dNorm * 2.0, u_flowContour) * u_flowRep;
    float nz = vnoise(fp * 3.0 + vec2(u_time * 0.15, -u_time * 0.1));
    phase += u_flowDistort * (nz - 0.5);
    phase -= u_time * u_flowSpeed;
    float fblur = 0.04 + 0.3 * u_flowSoft;
    float shift = u_flowShift * 0.06;
    vec3 flowC = vec3(
      chromeRamp(fract(phase + shift), fblur),
      chromeRamp(fract(phase), fblur),
      chromeRamp(fract(phase - shift), fblur)
    );
    // Keep the 3D shading: stripes are lit by the env luminance.
    envC = mix(envC, flowC * (0.35 + 0.9 * envL), u_flow);
  }

  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 5.0) * u_fresnel * 0.7;
  vec3 col = u_tint * envC + u_tint * rim * (0.35 + 0.65 * horizon);
  // Soft shoulder above 0.75 so highlights roll into white instead of clipping.
  vec3 hi = max(col - 0.75, 0.0);
  col = clamp(min(col, vec3(0.75)) + hi / (1.0 + 2.0 * hi), 0.0, 1.0);
  // Blue-noise-ish dither kills banding in the smooth dark gradients.
  col += (hash21(gl_FragCoord.xy) - 0.5) * 0.008;
  col = clamp(col, 0.0, 1.0);

  float alpha = smoothstep(0.0, 1.5, d);
  gl_FragColor = vec4(col, alpha);
}
