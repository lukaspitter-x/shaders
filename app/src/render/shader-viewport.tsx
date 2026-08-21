import { useEffect, useRef, useState } from 'react';
import type { ParsedShader, ShaderValues } from '@/glsl/parse-annotations';
import type { LintFinding } from '@/glsl/lint-pencil';
import { createShaderRenderer, type ShaderRenderer } from './webgl-quad';
import { generateSdf, resampleSdfBspline, type ShapeDef } from './sdf-shapes';

/** Cap the SDF texture's long side (uploads yield a 2048 B-spline-upsampled grid). */
const SDF_MAX = 2048;

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
  shapeScale = 1,
  lint,
  previewScale = 'full',
}: {
  parsed: ParsedShader;
  fragSource: string;
  values: ShaderValues;
  running: boolean;
  /** Host shape: feeds `u_shape` and clips the fill. `null` = full background. */
  shape: ShapeDef | null;
  /** User size multiplier for custom shapes (1 = fit to canvas). */
  shapeScale?: number;
  lint: LintFinding[];
  /** Grid preview scale: 'full' = native resolution, 1–4 = one cell = N pixels. */
  previewScale?: 'full' | 1 | 2 | 3 | 4;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const displayRef = useRef<HTMLCanvasElement>(null);
  const displayCtxRef = useRef<CanvasRenderingContext2D | null>(null);
  const rendererRef = useRef<ShaderRenderer | null>(null);
  const valuesRef = useRef(values);
  const shapeRef = useRef(shape);
  const shapeScaleRef = useRef(shapeScale);
  const sizeRef = useRef({ w: 1, h: 1 });
  const timeRef = useRef(0);
  const mouseRef = useRef<[number, number]>([0, 0]);
  const previewScaleRef = useRef(previewScale);
  const [error, setError] = useState<string | null>(null);

  // Keep the loop's view of settings/shape current without re-running effects.
  valuesRef.current = values;
  shapeRef.current = shape;
  shapeScaleRef.current = shapeScale;
  previewScaleRef.current = previewScale;

  /** Compute the backing resolution. In scale mode, render square at full res. */
  const resolveSize = (): { w: number; h: number } => {
    if (previewScaleRef.current === 'full') return sizeRef.current;
    const dim = Math.min(sizeRef.current.w, sizeRef.current.h);
    return { w: dim, h: dim };
  };

  /** Copy GL canvas → 2D display canvas with high-quality downsampling. */
  const copyToDisplay = () => {
    if (previewScaleRef.current === 'full') return;
    const gl = canvasRef.current;
    const disp = displayRef.current;
    if (!gl || !disp) return;
    if (!displayCtxRef.current) {
      displayCtxRef.current = disp.getContext('2d');
    }
    const ctx = displayCtxRef.current;
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const gridN = Math.floor(Number(valuesRef.current.u_gridSize) || 20);
    const scale = previewScaleRef.current as number;
    const backingSize = Math.round(gridN * scale * dpr);
    if (disp.width !== backingSize || disp.height !== backingSize) {
      disp.width = backingSize;
      disp.height = backingSize;
    }
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(gl, 0, 0, backingSize, backingSize);
  };

  // Draw one frame from the current refs. Cheap; safe to call any time.
  const drawFrame = () => {
    const r = rendererRef.current;
    const { w, h } = resolveSize();
    if (r && w > 0 && h > 0) {
      r.draw(valuesRef.current, timeRef.current, mouseRef.current, w, h);
      copyToDisplay();
    }
  };

  // (Re)build the host-shape SDF at the current size and feed it to the renderer.
  // `null` shape → no SDF (full background / no clip).
  const regenerateSdf = () => {
    const r = rendererRef.current;
    if (!r) return;
    let def = shapeRef.current;
    if (!def) {
      r.setSdf(null, 0, 0);
      return;
    }
    const { w, h } = sizeRef.current;
    if (w < 1 || h < 1) return;
    const scale = Math.max(w, h) > SDF_MAX ? SDF_MAX / Math.max(w, h) : 1;
    const texW = Math.max(1, Math.round(w * scale));
    const texH = Math.max(1, Math.round(h * scale));
    // Custom uploads: fit the image into the canvas (with a small margin),
    // scaled by the user's size dial (exact SDF scaling: s·d(p/s)), and
    // resample grid → texture with a C² B-spline so zoomed-in shapes don't
    // grow sawtooth facets from bilinear gradient kinks.
    if (def.custom && def.grid) {
      const canvasAspect = w / h;
      const fit =
        Math.min(1, canvasAspect / (def.aspect ?? 1)) * 0.92 * (shapeScaleRef.current || 1);
      const normalized = resampleSdfBspline(def.grid, texW, texH, canvasAspect, fit);
      const px = new Float32Array(normalized.length);
      for (let i = 0; i < px.length; i++) px[i] = normalized[i] * h;
      r.setSdf(px, texW, texH);
      return;
    }
    if (def.custom) {
      // Custom shape without a grid (shouldn't happen) — bilinear fallback.
      const canvasAspect = w / h;
      const fit =
        Math.min(1, canvasAspect / (def.aspect ?? 1)) * 0.92 * (shapeScaleRef.current || 1);
      const base = def;
      def = { ...base, sample: (px2, py2) => base.sample(px2 / fit, py2 / fit) * fit };
    }
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

    // Track cursor in gl_FragCoord space (origin bottom-left, device pixels).
    const onPointerMove = (e: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      mouseRef.current = [
        (e.clientX - rect.left) * dpr,
        (rect.bottom - e.clientY) * dpr,
      ];
    };
    canvas.addEventListener('pointermove', onPointerMove);

    return () => {
      canvas.removeEventListener('pointermove', onPointerMove);
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
    loadedImagesRef.current = {};
    regenerateSdf();
    drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fragSource]);

  // Rebuild the SDF when the host shape or its size dial changes.
  useEffect(() => {
    regenerateSdf();
    drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shape, shapeScale]);

  // Load user images into GL textures when their blob URLs change.
  const loadedImagesRef = useRef<Record<string, string>>({});
  useEffect(() => {
    const r = rendererRef.current;
    if (!r) return;
    for (const name of parsed.images) {
      const url = values[name];
      if (typeof url !== 'string' || url === loadedImagesRef.current[name]) continue;
      loadedImagesRef.current[name] = url;
      if (!url) {
        r.setImage(name, null);
        drawFrame();
        continue;
      }
      const img = new Image();
      img.onload = () => {
        r.setImage(name, img);
        drawFrame();
      };
      img.src = url;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [values, parsed]);

  // Redraw on settings edits while paused (the loop covers the running case).
  useEffect(() => {
    if (!running) drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [values]);

  // Redraw when the preview scale changes; reset display context on mode switch.
  useEffect(() => {
    displayCtxRef.current = null;
    drawFrame();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [previewScale]);

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

  const lintErrors = lint.filter((f) => f.severity === 'error');
  const lintWarnings = lint.filter((f) => f.severity === 'warning');

  const scaledCssPx = previewScale !== 'full'
    ? Math.floor(Number(values.u_gridSize) || 20) * previewScale
    : 0;

  return (
    <div className={`relative h-full w-full${previewScale !== 'full' ? ' flex items-center justify-center' : ''}`}>
      <canvas
        ref={canvasRef}
        className={previewScale === 'full' ? 'block h-full w-full' : 'absolute w-0 h-0 overflow-hidden'}
      />
      {previewScale !== 'full' && (
        <canvas
          ref={displayRef}
          className="block"
          style={{ width: scaledCssPx, height: scaledCssPx }}
        />
      )}
      {error && (
        <div className="absolute inset-0 flex items-center justify-center p-6">
          <pre className="max-w-full overflow-auto whitespace-pre-wrap rounded-md border border-destructive/40 bg-destructive/10 p-3 text-[11px] leading-snug text-destructive">
            {error}
          </pre>
        </div>
      )}
      {!error && lint.length > 0 && (
        <div className="absolute bottom-0 left-0 right-0 max-h-[40%] overflow-auto bg-background/90 backdrop-blur-sm border-t border-border">
          <div className="px-3 py-1.5 text-[11px] font-medium text-muted-foreground border-b border-border">
            Pencil compat — {lintErrors.length ? `${lintErrors.length} error${lintErrors.length > 1 ? 's' : ''}` : ''}{lintErrors.length && lintWarnings.length ? ', ' : ''}{lintWarnings.length ? `${lintWarnings.length} warning${lintWarnings.length > 1 ? 's' : ''}` : ''}
          </div>
          <ul className="py-1">
            {lint.map((f, i) => (
              <li key={i} className="flex gap-2 px-3 py-1">
                <span className={`shrink-0 text-[10px] font-medium tabular-nums ${f.severity === 'error' ? 'text-destructive' : 'text-yellow-500'}`}>
                  L{f.line}
                </span>
                <div className="min-w-0 text-[11px] leading-snug">
                  <span className="text-foreground">{f.message}</span>
                  {f.suggestion && (
                    <span className="text-muted-foreground"> — {f.suggestion}</span>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
