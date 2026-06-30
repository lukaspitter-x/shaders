/** @resolution */
uniform vec2 u_resolution;

/** @mouse */
uniform vec2 u_mouse;

/** @time */
uniform float u_time;

/**
 * Radius of the glow around the cursor, as a fraction of the shorter side.
 * @label Radius
 * @default 0.25
 * @range 0.05, 0.8
 */
uniform float u_radius;

/**
 * @label Color
 * @color
 * @default #4af0c0
 */
uniform vec3 u_color;

/**
 * How quickly the glow fades at the edge.
 * @label Falloff
 * @default 2.5
 * @range 0.5, 8
 */
uniform float u_falloff;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 muv = u_mouse / u_resolution;
  float d = distance(uv, muv);
  float r = u_radius;
  float glow = pow(clamp(1.0 - d / r, 0.0, 1.0), u_falloff);

  float pulse = 0.85 + 0.15 * sin(u_time * 2.0);
  vec3 col = u_color * glow * pulse;

  gl_FragColor = vec4(col, 1.0);
}
