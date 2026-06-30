/**
 * Minimal WebGL2 full-screen-quad renderer. Compiles a Pencil-style fragment
 * shader (wrapped in the compat prelude), introspects its active uniforms, and
 * draws a single triangle each frame binding system uniforms (resolution, time)
 * + user settings by name. The thin React shell (shader-viewport.tsx) owns the
 * canvas, the clock, and the render loop.
 */
import type { ParsedShader, ShaderValues } from '@/glsl/parse-annotations';
import {
  FULLSCREEN_VERTEX,
  PRELUDE_LINE_COUNT,
  wrapPencilFragment,
} from '@/glsl/pencil-prelude';
import { hexToRgb } from '@/lib/hex';

interface ActiveUniform {
  name: string;
  type: number;
  location: WebGLUniformLocation | null;
}

export type SetShaderResult = { ok: true } | { ok: false; error: string };

export interface ShaderRenderer {
  setShader(parsed: ParsedShader, fragSource: string): SetShaderResult;
  /** Upload the host-shape SDF for `@sdf` fills (R channel = px distance). */
  setSdf(data: Float32Array | null, width: number, height: number): void;
  draw(values: ShaderValues, timeSeconds: number, mouse: [number, number], width: number, height: number): void;
  dispose(): void;
}

/** Rewrite the prelude-offset line numbers in a compile log back to user lines. */
function remapErrorLines(log: string): string {
  return log.replace(/0:(\d+)/g, (_, n: string) => {
    const line = Math.max(1, Number(n) - PRELUDE_LINE_COUNT + 1);
    return `line ${line}`;
  });
}

export function createShaderRenderer(canvas: HTMLCanvasElement): ShaderRenderer | null {
  const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: false });
  if (!gl) return null;

  const vao = gl.createVertexArray();
  let program: WebGLProgram | null = null;
  let uniforms: ActiveUniform[] = [];
  let system: ParsedShader['system'] = {};

  // Host-shape SDF texture for `@sdf` fills (R16F, linear). Null until uploaded.
  let sdfTexture: WebGLTexture | null = null;
  let hasSdf = false;

  function setSdf(data: Float32Array | null, width: number, height: number): void {
    if (!sdfTexture) sdfTexture = gl!.createTexture();
    gl!.bindTexture(gl!.TEXTURE_2D, sdfTexture);
    // `null` (None / full background) → a 1×1 zero field: u_shape reads 0
    // everywhere (the empty-rectangle case, D8) and the clip is turned off.
    if (data) {
      gl!.texImage2D(gl!.TEXTURE_2D, 0, gl!.R16F, width, height, 0, gl!.RED, gl!.FLOAT, data);
      hasSdf = true;
    } else {
      gl!.texImage2D(gl!.TEXTURE_2D, 0, gl!.R16F, 1, 1, 0, gl!.RED, gl!.FLOAT, new Float32Array([0]));
      hasSdf = false;
    }
    gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MIN_FILTER, gl!.LINEAR);
    gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MAG_FILTER, gl!.LINEAR);
    gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_S, gl!.CLAMP_TO_EDGE);
    gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.CLAMP_TO_EDGE);
  }

  function compile(type: number, src: string): WebGLShader | string {
    const sh = gl!.createShader(type)!;
    gl!.shaderSource(sh, src);
    gl!.compileShader(sh);
    if (!gl!.getShaderParameter(sh, gl!.COMPILE_STATUS)) {
      const log = gl!.getShaderInfoLog(sh) ?? 'unknown compile error';
      gl!.deleteShader(sh);
      return log;
    }
    return sh;
  }

  function setShader(parsed: ParsedShader, fragSource: string): SetShaderResult {
    const vs = compile(gl!.VERTEX_SHADER, FULLSCREEN_VERTEX);
    if (typeof vs === 'string') return { ok: false, error: vs };
    const fs = compile(gl!.FRAGMENT_SHADER, wrapPencilFragment(fragSource));
    if (typeof fs === 'string') {
      gl!.deleteShader(vs);
      return { ok: false, error: remapErrorLines(fs) };
    }

    const prog = gl!.createProgram()!;
    gl!.attachShader(prog, vs);
    gl!.attachShader(prog, fs);
    gl!.linkProgram(prog);
    gl!.deleteShader(vs);
    gl!.deleteShader(fs);
    if (!gl!.getProgramParameter(prog, gl!.LINK_STATUS)) {
      const log = gl!.getProgramInfoLog(prog) ?? 'link error';
      gl!.deleteProgram(prog);
      return { ok: false, error: log };
    }

    if (program) gl!.deleteProgram(program);
    program = prog;
    system = parsed.system;
    uniforms = [];
    const count = gl!.getProgramParameter(prog, gl!.ACTIVE_UNIFORMS) as number;
    for (let i = 0; i < count; i++) {
      const info = gl!.getActiveUniform(prog, i);
      if (!info) continue;
      uniforms.push({
        name: info.name,
        type: info.type,
        location: gl!.getUniformLocation(prog, info.name),
      });
    }
    return { ok: true };
  }

  function draw(values: ShaderValues, time: number, mouse: [number, number], width: number, height: number): void {
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    gl!.viewport(0, 0, width, height);
    gl!.clearColor(0, 0, 0, 0);
    gl!.clear(gl!.COLOR_BUFFER_BIT);
    if (!program) return;

    gl!.useProgram(program);
    gl!.bindVertexArray(vao);

    // The SDF lives on texture unit 0 — sampled by `u_shape` (if the shader
    // declares `@sdf`) and by the compositor's `_pencilClip` (layer clip).
    if (sdfTexture) {
      gl!.activeTexture(gl!.TEXTURE0);
      gl!.bindTexture(gl!.TEXTURE_2D, sdfTexture);
    }

    for (const u of uniforms) {
      if (!u.location) continue;
      switch (u.name) {
        case system.resolution:
          gl!.uniform2f(u.location, width, height);
          continue;
        case system.time:
          gl!.uniform1f(u.location, time);
          continue;
        case system.mouse:
          gl!.uniform2f(u.location, mouse[0], mouse[1]);
          continue;
        case system.sdf:
        case '_pencilClip':
          gl!.uniform1i(u.location, 0);
          continue;
        case '_pencilClipRes':
          gl!.uniform2f(u.location, width, height);
          continue;
        case '_pencilClipOn':
          // Clip to the shape only when a real SDF is loaded (not None).
          gl!.uniform1f(u.location, hasSdf ? 1 : 0);
          continue;
      }

      const val = values[u.name];
      if (val === undefined) continue;
      if (u.type === gl!.FLOAT) {
        gl!.uniform1f(u.location, Number(val));
      } else if (u.type === gl!.FLOAT_VEC3 && typeof val === 'string') {
        const c = hexToRgb(val);
        gl!.uniform3f(u.location, c.r / 255, c.g / 255, c.b / 255);
      }
    }

    gl!.drawArrays(gl!.TRIANGLES, 0, 3);
  }

  function dispose(): void {
    if (program) gl!.deleteProgram(program);
    if (vao) gl!.deleteVertexArray(vao);
    if (sdfTexture) gl!.deleteTexture(sdfTexture);
    program = null;
    uniforms = [];
    sdfTexture = null;
  }

  return { setShader, setSdf, draw, dispose };
}
