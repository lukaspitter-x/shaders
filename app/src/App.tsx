import { useEffect, useMemo, useState } from 'react';
import { Download, Pause, Play } from 'lucide-react';
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
import { EXPERIMENTS } from '@/experiments/registry';

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
  const [selectedId, setSelectedId] = useState(EXPERIMENTS[0]?.id);
  const [running, setRunning] = useState(true);
  const [fpsVisible, setFpsVisible] = useState(true);
  const [fpsLogging, setFpsLogging] = useState(false);

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

  const selectedShape: ShapeDef | null =
    shapeId !== 'none'
      ? (shapes.find((s) => s.id === shapeId) ?? null)
      : requiresShape
        ? (shapes.find((s) => s.id === 'rounded-rect') ?? shapes[0] ?? null) // never hostless → black
        : null;

  // Settings values + undo history reset when the shader changes; the shape
  // default follows the shader type — a real shape for `@sdf` (shape-aware)
  // shaders, None (full background) for generative ones.
  const [values, setValues] = useState<ShaderValues>(() => parsed?.defaults ?? {});
  const [history, setHistory] = useState<History<ShaderValues>>(() => emptyHistory());
  useEffect(() => {
    setValues(parsed?.defaults ?? {});
    setHistory(emptyHistory());
    setShapeId(parsed?.system.sdf ? 'rounded-rect' : 'none');
  }, [parsed]);

  // Safety: a shape-aware shader must never be left on "None" (empty SDF → black) —
  // coerce to a real host if it ever is (e.g. stale state from before this guard).
  useEffect(() => {
    if (requiresShape && shapeId === 'none') setShapeId('rounded-rect');
  }, [requiresShape, shapeId]);

  const onUploadShape = async (file: File) => {
    try {
      const sdf = await imageToSdf(file);
      const id = `custom-${Date.now()}`;
      const label = file.name.replace(/\.[^.]+$/, '') || 'Custom';
      setCustomShapes((prev) => [...prev, makeCustomShape(sdf, id, label)]);
      setShapeId(id);
    } catch (err) {
      console.error('[shape upload]', err);
    }
  };

  // Record the PRE-edit snapshot (coalesced per control key so a slider drag is
  // one undo step), then apply the edit.
  const onChange = (key: string, value: ShaderValues[string]) => {
    setHistory((h) => record(h, values, key, performance.now()));
    setValues((prev) => ({ ...prev, [key]: value }));
  };

  const doUndo = () => {
    const r = histUndo(history, values);
    if (!r) return;
    setHistory(r.history);
    setValues(r.restore);
  };
  const doRedo = () => {
    const r = histRedo(history, values);
    if (!r) return;
    setHistory(r.history);
    setValues(r.restore);
  };

  // ⌘Z / ⌘⇧Z (and Ctrl on non-mac), except while editing a text field.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== 'z') return;
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
      e.preventDefault();
      if (e.shiftKey) doRedo();
      else doUndo();
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
                onSelect={setShapeId}
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
              title={running ? 'Pause' : 'Play'}
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
            />
          </ErrorBoundary>
        )}
      </div>
    </div>
  );
}
