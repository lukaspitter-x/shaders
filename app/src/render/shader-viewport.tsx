import { useEffect, useRef, useState } from 'react';
import type { ParsedShader, ShaderValues } from '@/glsl/parse-annotations';
import { createShaderRenderer, type ShaderRenderer } from './webgl-quad';
import { generateSdf, type ShapeDef } from './sdf-shapes';

/** Cap the SDF texture's long side — the field is smooth, so this is plenty. */
const SDF_MAX = 512;

/**
 * The shader preview. Owns the canvas, the animation clock, and the render
 * loop; the renderer (webgl-quad) is a plain imperative helper it drives.
 *
 * Per the build kit: the per-frame loop never calls setState — it reads the
 * latest settings from a ref and draws imperatively, so editing 60 controls
 * can't churn React at 60fps. setState is used only for one-off compile errors.
 */
export function ShaderViewport({
  parsed,
  fragSource,
  values,
  running,
  shape,
}: {
  parsed: ParsedShader;
  fragSource: string;
  values: ShaderValues;
  running: boolean;
  /** Host shape: feeds `u_shape` and clips the fill. `null` = full background. */
  shape: ShapeDef | null;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<ShaderRenderer | null>(null);
  const valuesRef = useRef(values);
  const shapeRef = useRef(shape);
  const sizeRef = useRef({ w: 1, h: 1 });
  const timeRef = useRef(0);
  const [error, setError] = useState<string | null>(null);

  // Keep the loop's view of settings/shape current without re-running effects.
  valuesRef.current = values;
  shapeRef.current = shape;

  // Draw one frame from the current refs. Cheap; safe to call any time.
  const drawFrame = () => {
    const r = rendererRef.current;
    const { w, h } = sizeRef.current;
    if (r && w > 0 && h > 0) r.draw(valuesRef.current, timeRef.current, w, h);
  };

  // (Re)build the host-shape SDF at the current size and feed it to the renderer.
  // `null` shape → no SDF (full background / no clip).
  const regenerateSdf = () => {
    const r = rendererRef.current;
    if (!r) return;
    const def = shapeRef.current;
    if (!def) {
      r.setSdf(null, 0, 0);
      return;
    }
    const { w, h } = sizeRef.current;
    if (w < 1 || h < 1) return;
    const scale = Math.max(w, h) > SDF_MAX ? SDF_MAX / Math.max(w, h) : 1;
    const texW = Math.max(1, Math.round(w * scale));
    const texH = Math.max(1, Math.round(h * scale));
    r.setSdf(generateSdf(def, texW, texH, w / h, h), texW, texH);
  };

  // Create the GL renderer once, on mount.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const r = createShaderRenderer(canvas);
    if (!r) {
      setError('WebGL2 is not available in this browser.');
      return;
    }
    rendererRef.current = r;

    // Track the container size in device pixels (capped DPR for perf).
    const ro = new ResizeObserver((entries) => {
      const cr = entries[0].contentRect;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      sizeRef.current = {
        w: Math.max(1, Math.round(cr.width * dpr)),
        h: Math.max(1, Math.round(cr.height * dpr)),
      };
      regenerateSdf();
      drawFrame();
    });
    ro.observe(canvas.parentElement ?? canvas);

    return () => {
      ro.disconnect();
      r.dispose();
      rendererRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // (Re)compile whenever the shader source changes; rebuild its SDF too.
  useEffect(() => {
    const r = rendererRef.current;
    if (!r) return;
    const res = r.setShader(parsed, fragSource);
    setError(res.ok ? null : res.error);
    timeRef.current = 0;
    regenerateSdf();
    drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fragSource]);

  // Rebuild the SDF when the host shape changes.
  useEffect(() => {
    regenerateSdf();
    drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shape]);

  // Redraw on settings edits while paused (the loop covers the running case).
  useEffect(() => {
    if (!running) drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [values]);

  // The animation loop — only mounted while running. Advances the clock by real
  // elapsed time so pause/resume doesn't jump. (The FPS readout is a separate
  // singleton monitor in the top bar; this loop only renders.)
  useEffect(() => {
    if (!running) return;
    let raf = 0;
    let last = performance.now();
    const loop = () => {
      const now = performance.now();
      timeRef.current += (now - last) / 1000;
      last = now;
      drawFrame();
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  return (
    <div className="relative h-full w-full">
      <canvas ref={canvasRef} className="block h-full w-full" />
      {error && (
        <div className="absolute inset-0 flex items-center justify-center p-6">
          <pre className="max-w-full overflow-auto whitespace-pre-wrap rounded-md border border-destructive/40 bg-destructive/10 p-3 text-[11px] leading-snug text-destructive">
            {error}
          </pre>
        </div>
      )}
    </div>
  );
}
