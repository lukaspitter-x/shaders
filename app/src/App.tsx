import { useEffect, useMemo, useState } from 'react';
import { Download, Pause, Play } from 'lucide-react';
import { cn } from '@/lib/cn';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import { ErrorBoundary } from '@/components/error-boundary';
import { UndoRedoButtons } from '@/components/undo-redo-buttons';
import { ShapePicker } from '@/components/shape-picker';
import { LintBadge } from '@/components/lint-badge';
import { FpsPanel } from '@/perf/fps-panel';
import { SettingsColumn } from '@/settings/settings-column';
import { parseShader, sanitizeValues, type ShaderValues } from '@/glsl/parse-annotations';
import { lintPencil } from '@/glsl/lint-pencil';
import { ShaderViewport } from '@/render/shader-viewport';
import { BUILTIN_SHAPES, makeCustomShape, type ShapeDef } from '@/render/sdf-shapes';
import { imageToSdf } from '@/render/image-sdf';
import {
  canRedo,
  canUndo,
  emptyHistory,
  record,
  redo as histRedo,
  undo as histUndo,
  type History,
} from '@/lib/history';
import { readJson, writeJson, useLocalStorage } from '@/lib/local-storage';
import { EXPERIMENTS } from '@/experiments/registry';

// Per-browser persistence keys. Settings values and the host-shape pick are
// keyed per shader so each shader keeps its own edits across reloads.
const valuesKey = (id: string) => `values:${id}`;
const shapeKey = (id: string) => `shape:${id}`;
const SELECTED_KEY = 'selected';

type PreviewScale = 'full' | 1 | 2 | 3 | 4;
const PREVIEW_SCALES: { value: PreviewScale; label: string }[] = [
  { value: 'full', label: 'Full' },
  { value: 1, label: '1x' },
  { value: 2, label: '2x' },
  { value: 3, label: '3x' },
  { value: 4, label: '4x' },
];

/** A stored shape id is usable only if it's "none" or a built-in (custom uploads
 *  are in-memory, so they don't survive a restart). */
const isUsableShapeId = (id: string | null): id is string =>
  id === 'none' || BUILTIN_SHAPES.some((s) => s.id === id);

/**
 * App shell — top bar + viewport + right settings column (no timeline). Layout
 * mirrors flip: shader selector on the left, FPS panel, undo/redo, then the
 * preview-input controls (shape picker, play/pause) pushed to the right.
 *
 * The selected shader's annotated `.glsl` is parsed into a schema (driving the
 * panel) and a uniform manifest (which the viewport binds). One file is the
 * shader and the schema both.
 */
export default function App() {
  // Remember the last-open shader across reloads (falling back if it's gone).
  const [selectedId, setSelectedId] = useState<string | undefined>(() => {
    const saved = readJson<string | null>(SELECTED_KEY, null);
    return saved && EXPERIMENTS.some((e) => e.id === saved) ? saved : EXPERIMENTS[0]?.id;
  });
  useEffect(() => {
    if (selectedId) writeJson(SELECTED_KEY, selectedId);
  }, [selectedId]);

  const [running, setRunning] = useLocalStorage('running', true);
  const [fpsVisible, setFpsVisible] = useLocalStorage('fpsVisible', true);
  const [fpsLogging, setFpsLogging] = useLocalStorage('fpsLogging', false);

  // Host shape: built-ins + user uploads (in-memory only — no persistence yet).
  const [customShapes, setCustomShapes] = useState<ShapeDef[]>([]);
  const [shapeId, setShapeId] = useState('none');
  const shapes = useMemo(() => [...BUILTIN_SHAPES, ...customShapes], [customShapes]);

  const selected = EXPERIMENTS.find((e) => e.id === selectedId);
  const parsed = useMemo(() => (selected ? parseShader(selected.source) : null), [selected]);
  const lint = useMemo(() => (selected ? lintPencil(selected.source) : []), [selected]);
  // Shape-aware (`@sdf`) shaders need a host shape — "None" feeds an empty SDF, so
  // the shader renders nothing (faithful to a Pencil rectangle, but a dead end here).
  const requiresShape = !!parsed?.system.sdf;

  // Grid preview scale — only meaningful for shaders with a u_gridSize uniform.
  const [previewScale, setPreviewScale] = useState<PreviewScale>('full');
  const hasGrid = parsed?.schema.some((c) => c.key === 'u_gridSize') ?? false;

  const selectedShape: ShapeDef | null =
    shapeId !== 'none'
      ? (shapes.find((s) => s.id === shapeId) ?? null)
      : requiresShape
        ? (shapes.find((s) => s.id === 'rounded-rect') ?? shapes[0] ?? null) // never hostless → black
        : null;

  // Settings values + undo history reset when the shader changes; the shape
  // default follows the shader type — a real shape for `@sdf` (shape-aware)
  // shaders, None (full background) for generative ones.
  const [values, setValues] = useState<ShaderValues>(() => {
    const id = EXPERIMENTS.find((e) => e.id === selectedId)?.id;
    return (id ? readJson<ShaderValues | null>(valuesKey(id), null) : null) ?? parsed?.defaults ?? {};
  });
  const [history, setHistory] = useState<History<ShaderValues>>(() => emptyHistory());
  // On a shader switch, restore that shader's persisted settings + shape (or its
  // defaults). Values are validated against the live schema on read by
  // `effectiveValues`/`sanitizeValues` below — stale stored data can't render wrong.
  useEffect(() => {
    if (!parsed || !selected) {
      setValues({});
      setHistory(emptyHistory());
      setShapeId('none');
      return;
    }
    const storedValues = readJson<ShaderValues | null>(valuesKey(selected.id), null);
    setValues(storedValues ?? parsed.defaults);
    setHistory(emptyHistory());
    const storedShape = readJson<string | null>(shapeKey(selected.id), null);
    setShapeId(
      isUsableShapeId(storedShape)
        ? storedShape
        : parsed.system.sdf
          ? 'rounded-rect'
          : 'none',
    );
  }, [parsed, selected]);

  // Pick a host shape and persist it for the current shader.
  const selectShape = (id: string) => {
    setShapeId(id);
    if (selectedId) writeJson(shapeKey(selectedId), id);
  };

  // Safety: a shape-aware shader must never be left on "None" (empty SDF → black) —
  // coerce to a real host if it ever is (e.g. stale state from before this guard).
  useEffect(() => {
    if (requiresShape && shapeId === 'none') selectShape('rounded-rect');
  }, [requiresShape, shapeId]);

  const onUploadShape = async (file: File) => {
    try {
      const sdf = await imageToSdf(file);
      const id = `custom-${Date.now()}`;
      const label = file.name.replace(/\.[^.]+$/, '') || 'Custom';
      setCustomShapes((prev) => [...prev, makeCustomShape(sdf, id, label)]);
      // Uploads are in-memory only; persisting the id would dangle after reload.
      setShapeId(id);
    } catch (err) {
      console.error('[shape upload]', err);
    }
  };

  // Record the PRE-edit snapshot (coalesced per control key so a slider drag is
  // one undo step), then apply the edit.
  const onChange = (key: string, value: ShaderValues[string]) => {
    setHistory((h) => record(h, values, key, performance.now()));
    const next = { ...values, [key]: value };
    setValues(next);
    if (selectedId) writeJson(valuesKey(selectedId), next);
  };

  const doUndo = () => {
    const r = histUndo(history, values);
    if (!r) return;
    setHistory(r.history);
    setValues(r.restore);
    if (selectedId) writeJson(valuesKey(selectedId), r.restore);
  };
  const doRedo = () => {
    const r = histRedo(history, values);
    if (!r) return;
    setHistory(r.history);
    setValues(r.restore);
    if (selectedId) writeJson(valuesKey(selectedId), r.restore);
  };

  // Keyboard shortcuts. Both skip text fields so typing isn't hijacked:
  //   ⌘Z / ⌘⇧Z (Ctrl on non-mac) — undo / redo
  //   Space — toggle play/pause
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      const typing =
        !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        if (typing) return;
        e.preventDefault();
        if (e.shiftKey) doRedo();
        else doUndo();
        return;
      }

      if (e.key === ' ' || e.code === 'Space') {
        if (typing) return;
        // A focused button/select handles Space natively (it activates the
        // control) — don't also toggle, or the two cancel out or double-fire.
        if (t && (t.tagName === 'BUTTON' || t.getAttribute('role') === 'button')) return;
        e.preventDefault();
        setRunning((r) => !r);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const downloadGlsl = () => {
    if (!selected) return;
    const blob = new Blob([selected.source], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${selected.id}.glsl`;
    a.click();
    URL.revokeObjectURL(url);
  };

  // Defaults under values: on a shader switch `values` lags one render, so a
  // new control could otherwise read an undefined key. Defaults backfill any
  // missing key; edits in `values` win. Then sanitize (clamp) on read.
  const effectiveValues = useMemo<ShaderValues>(
    () => sanitizeValues(parsed?.schema ?? [], { ...(parsed?.defaults ?? {}), ...values }),
    [parsed, values],
  );

  return (
    <div className="flex h-[100dvh] flex-col bg-background text-foreground">
      {/* Top bar: shader selector + perf + undo/redo (left) · preview inputs (right) */}
      <header className="flex h-10 shrink-0 items-center gap-3 border-b border-border px-3 sm:px-4">
        <span className="logo hidden sm:inline">shaders</span>
        <div className="w-40 min-w-0 sm:w-48">
          <Select value={selectedId} onValueChange={setSelectedId}>
            <SelectTrigger>
              <SelectValue placeholder="Shader" />
            </SelectTrigger>
            <SelectContent>
              {EXPERIMENTS.map((e) => (
                <SelectItem key={e.id} value={e.id}>
                  {e.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <FpsPanel
          visible={fpsVisible}
          logging={fpsLogging}
          onToggleVisible={() => setFpsVisible((v) => !v)}
          onToggleLogging={() => setFpsLogging((v) => !v)}
        />
        <UndoRedoButtons
          canUndo={canUndo(history)}
          canRedo={canRedo(history)}
          onUndo={doUndo}
          onRedo={doRedo}
        />
        {selected && <LintBadge findings={lint} />}

        <div className="ml-auto flex items-center gap-2">
          {selected && (
            <>
              <span className="heading">Shape</span>
              <ShapePicker
                shapes={shapes}
                value={shapeId}
                onSelect={selectShape}
                onUpload={onUploadShape}
                requiresShape={requiresShape}
              />
            </>
          )}
          {selected && (
            <Button
              variant="ghost"
              size="icon"
              aria-label="Download .glsl"
              title="Download .glsl"
              onClick={downloadGlsl}
            >
              <Download />
            </Button>
          )}
          {selected && (
            <Button
              variant="ghost"
              size="icon"
              aria-label={running ? 'Pause' : 'Play'}
              title={running ? 'Pause (Space)' : 'Play (Space)'}
              onClick={() => setRunning((r) => !r)}
            >
              {running ? <Pause /> : <Play />}
            </Button>
          )}
        </div>
      </header>

      {/* Body: viewport + settings column */}
      <div className="relative flex min-h-0 flex-1">
        <main className="flex min-w-0 flex-1 items-center justify-center overflow-hidden p-6">
          {selected && parsed ? (
            <div className="h-full w-full overflow-hidden rounded-lg border border-border">
              <ErrorBoundary key={selected.id} label="Viewport crashed">
                <ShaderViewport
                  parsed={parsed}
                  fragSource={selected.source}
                  values={effectiveValues}
                  running={running}
                  shape={selectedShape}
                  lint={lint}
                  previewScale={hasGrid ? previewScale : 'full'}
                />
              </ErrorBoundary>
            </div>
          ) : (
            <div className="max-w-sm text-center text-muted-foreground">
              <p className="heading mb-2">No shader selected</p>
              <p>
                Drop an annotated <code>.glsl</code> into <code>src/experiments/</code> and
                register it to preview it here.
              </p>
            </div>
          )}
        </main>

        {parsed && (
          <ErrorBoundary key={selectedId} label="Settings crashed">
            <SettingsColumn
              title="Settings"
              storageKey={selectedId}
              schema={parsed.schema}
              value={effectiveValues}
              defaults={parsed.defaults}
              onChange={onChange}
              header={
                hasGrid ? (
                  <div className="flex flex-col gap-2">
                    <span className="heading">Preview</span>
                    <div className="flex gap-1">
                      {PREVIEW_SCALES.map((s) => (
                        <button
                          key={String(s.value)}
                          type="button"
                          onClick={() => setPreviewScale(s.value)}
                          className={cn(
                            'flex-1 rounded-md px-2 py-1 text-xs font-medium transition-colors',
                            previewScale === s.value
                              ? 'bg-accent text-accent-foreground'
                              : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
                          )}
                        >
                          {s.label}
                        </button>
                      ))}
                    </div>
                  </div>
                ) : undefined
              }
            />
          </ErrorBoundary>
        )}
      </div>
    </div>
  );
}
