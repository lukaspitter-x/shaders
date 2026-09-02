/**
 * Pencil compatibility shim + a layer-clip compositor.
 *
 * Pencil shaders are written WebGL1-style (`gl_FragColor`, `texture2D`) but also
 * use the ES-3.00 `textureSize`, so they compile in neither pure dialect. We
 * wrap user code in a GLSL ES 3.00 prelude (replicating Pencil's transpile) so
 * the preview is what Pencil runs. See docs/decisions.md (D2).
 *
 * On top of that, we emulate Pencil's *layer clip*: a fill is clipped to the
 * silhouette of the layer it's applied to. We rename the user's `main` to
 * `_pencilUserMain` and supply our own `main` that calls it, then multiplies the
 * output alpha by the host-shape mask. This clips ANY shader (generative ones
 * included) to the selected shape, without touching the user's source. When no
 * shape is selected (`_pencilClipOn == 0`) the fill covers the whole layer.
 */
export const PENCIL_FRAGMENT_PRELUDE = `#version 300 es
precision highp float;
out vec4 fragColor;
#define gl_FragColor fragColor
#define texture2D texture
uniform sampler2D _pencilClip;
uniform vec2 _pencilClipRes;
uniform float _pencilClipOn;
uniform vec2 _pencilOrigin;
vec4 _pencilFragCoord;
#define gl_FragCoord _pencilFragCoord
#define main _pencilUserMain
`;

export const PENCIL_FRAGMENT_SUFFIX = `
#undef main
#undef gl_FragCoord
void main() {
  // Layer space: Pencil hands a fill its layer's bounds, so user code sees
  // coordinates relative to the host shape's box (see webgl-quad.ts).
  _pencilFragCoord = vec4(gl_FragCoord.xy - _pencilOrigin, gl_FragCoord.zw);
  _pencilUserMain();
  if (_pencilClipOn > 0.5) {
    float _d = texture2D(_pencilClip, gl_FragCoord.xy / _pencilClipRes).r;
    fragColor.a *= clamp(_d + 0.5, 0.0, 1.0);
  }
}
`;

/** Lines the prelude adds before user source, to map compile errors to user lines. */
export const PRELUDE_LINE_COUNT = PENCIL_FRAGMENT_PRELUDE.split('\n').length;

/** A full-screen triangle generated from gl_VertexID — no vertex buffers. */
export const FULLSCREEN_VERTEX = `#version 300 es
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
`;

export function wrapPencilFragment(userSource: string): string {
  return PENCIL_FRAGMENT_PRELUDE + userSource + PENCIL_FRAGMENT_SUFFIX;
}
