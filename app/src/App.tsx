import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, ClipboardCopy, Download, Pause, Play } from 'lucide-react';
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
import { parseShader, type ShaderValues } from '@/glsl/parse-annotations';
import { lintPencil } from '@/glsl/lint-pencil';
import { ShaderViewport } from '@/render/shader-viewport';
import { BUILTIN_SHAPES, makeCustomShape, type ShapeDef } from '@/render/sdf-shapes';
import { imageToSdf } from '@/render/image-sdf';
import {
  fileToDataUrl,
  loadStoredShapes,
  persistShape,
  removeStoredShape,
  storedShapeToFile,
} from '@/render/shape-store';
import {
  ENV_VIEW_PARSED,
  ENV_VIEW_SOURCE,
  SDF_VIEW_PARSED,
  SDF_VIEW_SOURCE,
  envPreviewAvailable,
  type ViewMode,
} from '@/render/view-modes';
import { readJson, writeJson, useLocalStorage } from '@/lib/local-storage';
import {
  bakeDefaults,
  downgradePencilDirectives,
  stripHiddenAnnotations,
} from '@/glsl/strip-annotations';
import { usePresets } from '@/presets/use-presets';
import { PresetSwitcher } from '@/presets/preset-switcher';
import { EXPERIMENTS } from '@/experiments/registry';

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

const isUsableShapeId = (id: string | null, shapes: ShapeDef[]): id is string =>
  id === 'none' || shapes.some((s) => s.id === id);

const labelFromFileName = (name: string) => name.replace(/\.[^.]+$/, '') || 'Custom';

export default function App() {
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

  const [customShapes, setCustomShapes] = useState<ShapeDef[]>([]);
  const [shapeId, setShapeId] = useState('none');
  const [shapeScales, setShapeScales] = useState<Record<string, number>>(() =>
    readJson('shapeScales', {}),
  );
  useEffect(() => {
    writeJson('shapeScales', shapeScales);
  }, [shapeScales]);
  const shapes = useMemo(() => [...BUILTIN_SHAPES, ...customShapes], [customShapes]);

  // Restore persisted uploads on startup: rebuild each SDF from the stored
  // original file, so pipeline improvements apply to old uploads too.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const stored = await loadStoredShapes();
      const defs: ShapeDef[] = [];
      for (const s of stored) {
        try {
          const sdf = await imageToSdf(await storedShapeToFile(s));
          defs.push(makeCustomShape(sdf, s.id, s.label));
        } catch (err) {
          console.error('[shapes] restore failed for', s.label, err);
        }
      }
      if (!cancelled && defs.length) setCustomShapes((prev) => [...defs, ...prev]);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const selected = EXPERIMENTS.find((e) => e.id === selectedId);
  const parsed = useMemo(() => (selected ? parseShader(selected.source) : null), [selected]);
  // Lint what Pencil will actually receive — the export path downgrades
  // workbench-only directives (@select/@switch/@step) to paste-safe @range.
  const lint = useMemo(
    () => (selected ? lintPencil(downgradePencilDirectives(selected.source)) : []),
    [selected],
  );
  const requiresShape = !!parsed?.system.sdf;

  const [previewScale, setPreviewScale] = useState<PreviewScale>('full');
  const hasGrid = parsed?.schema.some((c) => c.key === 'u_gridSize') ?? false;

  const selectedShape: ShapeDef | null =
    shapeId !== 'none'
      ? (shapes.find((s) => s.id === shapeId) ?? null)
      : requiresShape
        ? (shapes.find((s) => s.id === 'rounded-rect') ?? shapes[0] ?? null)
        : null;

  // Presets hook — replaces the old useState<ShaderValues> + localStorage persistence.
  const presetStore = usePresets(
    selectedId ?? '',
    parsed?.defaults ?? {},
    parsed?.schema,
  );

  // Restore shape on shader switch (and when async-restored uploads arrive,
  // so a persisted custom selection can win over the interim fallback).
  useEffect(() => {
    if (!parsed || !selected) {
      setShapeId('none');
      return;
    }
    const storedShape = readJson<string | null>(shapeKey(selected.id), null);
    setShapeId(
      isUsableShapeId(storedShape, shapes)
        ? storedShape
        : parsed.system.sdf
          ? 'rounded-rect'
          : 'none',
    );
  }, [parsed, selected, shapes]);

  const selectShape = (id: string) => {
    setShapeId(id);
    if (selectedId) writeJson(shapeKey(selectedId), id);
  };

  useEffect(() => {
    if (requiresShape && shapeId === 'none') selectShape('rounded-rect');
  }, [requiresShape, shapeId]);

  const onUploadShape = async (file: File) => {
    try {
      const sdf = await imageToSdf(file);
      const id = `custom-${Date.now()}`;
      const label = labelFromFileName(file.name);
      setCustomShapes((prev) => [...prev, makeCustomShape(sdf, id, label)]);
      selectShape(id);
      // Write-through persistence (best-effort — the shape works either way).
      void fileToDataUrl(file)
        .then((dataUrl) => persistShape({ id, label, name: file.name, type: file.type, dataUrl }))
        .catch((err) => console.error('[shape persist]', err));
    } catch (err) {
      console.error('[shape upload]', err);
    }
  };

  const onChange = (key: string, value: ShaderValues[string]) => {
    presetStore.setValue(key, value);
  };

  const shapeScale = selectedShape?.custom ? (shapeScales[selectedShape.id] ?? 1) : 1;

  const onDeleteShape = (id: string) => {
    setCustomShapes((prev) => prev.filter((s) => s.id !== id));
    setShapeScales((prev) => {
      const { [id]: _removed, ...rest } = prev;
      return rest;
    });
    if (shapeId === id) selectShape(requiresShape ? 'rounded-rect' : 'none');
    void removeStoredShape(id).catch((err) => console.error('[shape delete]', err));
  };

  // Viewport view mode: the experiment itself, its host SDF, or the chrome
  // env panorama. Debug modes swap only the VIEWPORT shader — settings, lint,
  // and export always follow the experiment.
  const [viewMode, setViewMode] = useLocalStorage<ViewMode>('viewMode', 'fill');
  const canSdfView = !!parsed?.system.sdf;
  const canEnvView = envPreviewAvailable(parsed);
  useEffect(() => {
    if ((viewMode === 'sdf' && !canSdfView) || (viewMode === 'env' && !canEnvView)) {
      setViewMode('fill');
    }
  }, [viewMode, canSdfView, canEnvView, setViewMode]);
  const viewParsed = viewMode === 'sdf' ? SDF_VIEW_PARSED : viewMode === 'env' ? ENV_VIEW_PARSED : parsed;
  const viewSource =
    viewMode === 'sdf' ? SDF_VIEW_SOURCE : viewMode === 'env' ? ENV_VIEW_SOURCE : selected?.source;

  const VIEW_MODES: { value: ViewMode; label: string; enabled: boolean; title: string }[] = [
    { value: 'fill', label: 'Fill', enabled: true, title: 'Render the shader' },
    { value: 'sdf', label: 'SDF', enabled: canSdfView, title: 'Inspect the host shape distance field' },
    { value: 'env', label: 'Env', enabled: canEnvView, title: 'Preview the procedural environment' },
  ];

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      const typing =
        !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);

      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
        if (typing) return;
        e.preventDefault();
        if (e.shiftKey) presetStore.redo();
        else presetStore.undo();
        return;
      }

      if (e.key === ' ' || e.code === 'Space') {
        if (typing) return;
        if (t && (t.tagName === 'BUTTON' || t.getAttribute('role') === 'button')) return;
        e.preventDefault();
        setRunning((r) => !r);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  // Export path: bake current values into @default so the tuned look (e.g. a
  // material preset) pastes into Pencil intact, then inline hidden uniforms.
  const exportGlsl = () =>
    selected
      ? stripHiddenAnnotations(
          bakeDefaults(selected.source, presetStore.values),
          presetStore.pencilKeys,
          presetStore.values,
        )
      : '';

  const [copied, setCopied] = useState(false);
  const copyTimer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(copyTimer.current), []);
  const copyGlsl = async () => {
    if (!selected) return;
    try {
      await navigator.clipboard.writeText(exportGlsl());
      setCopied(true);
      clearTimeout(copyTimer.current);
      copyTimer.current = setTimeout(() => setCopied(false), 1500);
    } catch (err) {
      console.error('[copy for pencil]', err);
    }
  };

  const downloadGlsl = () => {
    if (!selected) return;
    const blob = new Blob([exportGlsl()], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${selected.id}.glsl`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex h-[100dvh] flex-col bg-background text-foreground">
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
          canUndo={presetStore.canUndo}
          canRedo={presetStore.canRedo}
          onUndo={presetStore.undo}
          onRedo={presetStore.redo}
        />
        {selected && <LintBadge findings={lint} />}
        {selected && (canSdfView || canEnvView) && (
          <div className="flex rounded-md border border-border p-0.5">
            {VIEW_MODES.filter((m) => m.enabled).map((m) => (
              <button
                key={m.value}
                type="button"
                title={m.title}
                onClick={() => setViewMode(m.value)}
                className={cn(
                  'rounded px-2 py-0.5 text-[11px] font-medium transition-colors',
                  viewMode === m.value
                    ? 'bg-accent text-accent-foreground'
                    : 'text-muted-foreground hover:text-foreground',
                )}
              >
                {m.label}
              </button>
            ))}
          </div>
        )}

        <div className="ml-auto flex items-center gap-2">
          {selected && (
            <>
              <span className="heading">Shape</span>
              <ShapePicker
                shapes={shapes}
                value={shapeId}
                onSelect={selectShape}
                onUpload={onUploadShape}
                onDelete={onDeleteShape}
                requiresShape={requiresShape}
              />
              {selectedShape?.custom && (
                <input
                  type="range"
                  min={0.25}
                  max={2}
                  step={0.05}
                  value={shapeScale}
                  title={`Shape size ×${shapeScale.toFixed(2)} — double-click to reset`}
                  aria-label="Shape size"
                  className="w-24 accent-foreground"
                  onChange={(e) =>
                    setShapeScales((prev) => ({
                      ...prev,
                      [selectedShape.id]: Number(e.target.value),
                    }))
                  }
                  onDoubleClick={() =>
                    setShapeScales((prev) => ({ ...prev, [selectedShape.id]: 1 }))
                  }
                />
              )}
            </>
          )}
          {selected && (
            <Button
              variant="ghost"
              size="icon"
              aria-label="Copy for Pencil"
              title="Copy for Pencil (current values baked into @default)"
              onClick={copyGlsl}
            >
              {copied ? <Check /> : <ClipboardCopy />}
            </Button>
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

      <div className="relative flex min-h-0 flex-1">
        <main className="flex min-w-0 flex-1 items-center justify-center overflow-hidden p-6">
          {selected && parsed && viewParsed && viewSource ? (
            <div className="h-full w-full overflow-hidden rounded-lg border border-border">
              <ErrorBoundary key={`${selected.id}:${viewMode}`} label="Viewport crashed">
                <ShaderViewport
                  parsed={viewParsed}
                  fragSource={viewSource}
                  values={presetStore.values}
                  running={running}
                  shape={viewMode === 'env' ? null : selectedShape}
                  shapeScale={shapeScale}
                  lint={viewMode === 'fill' ? lint : []}
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
              value={presetStore.values}
              defaults={parsed.defaults}
              onChange={onChange}
              pencilKeys={presetStore.pencilKeys}
              onTogglePencil={presetStore.togglePencilKey}
              header={
                <div className="flex flex-col gap-3">
                  <PresetSwitcher store={presetStore} />
                  {hasGrid && (
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
                  )}
                </div>
              }
            />
          </ErrorBoundary>
        )}
      </div>
    </div>
  );
}
