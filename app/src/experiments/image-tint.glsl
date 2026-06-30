/** @resolution */
uniform vec2 u_resolution;

/**
 * Source image to process.
 * @label Image
 */
uniform sampler2D u_image;

/**
 * Tint color blended over the image.
 * @label Tint
 * @color
 * @default #4466ff
 */
uniform vec3 u_tint;

/**
 * How much tint to apply.
 * @label Tint Amount
 * @default 0.3
 * @range 0, 1
 */
uniform float u_amount;

/**
 * Vignette darkness at edges.
 * @label Vignette
 * @default 0.4
 * @range 0, 1
 */
uniform float u_vignette;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec4 tex = texture2D(u_image, uv);
  vec3 col = mix(tex.rgb, u_tint, u_amount);
  float d = distance(uv, vec2(0.5));
  col *= 1.0 - u_vignette * smoothstep(0.3, 0.8, d);
  gl_FragColor = vec4(col, tex.a);
}
