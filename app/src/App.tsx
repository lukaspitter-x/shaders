import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Check,
  ClipboardCopy,
  Download,
  MoreHorizontal,
  PanelRightClose,
  PanelRightOpen,
  Pause,
  Play,
} from 'lucide-react';
import { cn } from '@/lib/cn';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { ErrorBoundary } from '@/components/error-boundary';
import { UndoRedoButtons } from '@/components/undo-redo-buttons';
import { ShapePicker } from '@/components/shape-picker';
import { LintBadge } from '@/components/lint-badge';
import { FpsPanel } from '@/perf/fps-panel';
import { SettingsColumn } from '@/settings/settings-column';
import { SliderControl } from '@/settings/controls/slider-control';
import { parseShader, type ShaderValues } from '@/glsl/parse-annotations';
import { lintPencil } from '@/glsl/lint-pencil';
import { ShaderViewport } from '@/render/shader-viewport';
import { BUILTIN_SHAPES, makeCustomShape, type NormalizedSdf, type ShapeDef } from '@/render/sdf-shapes';
import { imageToSdf, type SdfSource } from '@/render/image-sdf';
import { blurField } from '@/render/edt';
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
import {
  readUiState,
  useLocalStorage,
  useTabState,
  writeUiState,
} from '@/lib/local-storage';
import {
  bakeDefaults,
  downgradePencilDirectives,
  stripHiddenAnnotations,
} from '@/glsl/strip-annotations';
import { usePresets } from '@/presets/use-presets';
import { PresetSwitcher } from '@/presets/preset-switcher';
import { EXPERIMENTS } from '@/experiments/registry';

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
    const saved = readUiState<string | null>(SELECTED_KEY, null);
    return saved && EXPERIMENTS.some((e) => e.id === saved) ? saved : EXPERIMENTS[0]?.id;
  });
  useEffect(() => {
    if (selectedId) writeUiState(SELECTED_KEY, selectedId);
  }, [selectedId]);

  const [running, setRunning] = useLocalStorage('running', true);
  const [fpsVisible, setFpsVisible] = useLocalStorage('fpsVisible', true);
  const [fpsLogging, setFpsLogging] = useLocalStorage('fpsLogging', false);
  const [settingsOpen, setSettingsOpen] = useLocalStorage(
    'settingsOpen',
    window.matchMedia('(min-width: 768px)').matches,
  );

  const [customShapes, setCustomShapes] = useState<ShapeDef[]>([]);
  const shapes = useMemo(() => [...BUILTIN_SHAPES, ...customShapes], [customShapes]);

  // Shape-field generation controls (persisted). Detail = raster/grid long
  // side; source = exact vector tracing vs rasterize+EDT (SVG only); smooth =
  // field blur radius in grid cells (rounds corners); expand = silhouette
  // offset in canvas px (bold/thin), applied at render time.
  const [sdfDetail, setSdfDetail] = useLocalStorage('sdfDetail', 1024);
  const [sdfSource, setSdfSource] = useLocalStorage<SdfSource>('sdfSource', 'exact');
  const [shapeSmooth, setShapeSmooth] = useLocalStorage('shapeSmooth', 0);
  const [shapeExpand, setShapeExpand] = useLocalStorage('shapeExpand', 0);

  const buildShapeSdf = async (file: File): Promise<NormalizedSdf> => {
    let sdf = await imageToSdf(file, sdfDetail, sdfSource);
    if (shapeSmooth > 0) {
      sdf = { ...sdf, data: blurField(sdf.data, sdf.width, sdf.height, shapeSmooth) };
    }
    return sdf;
  };

  // Restore persisted uploads on startup — and REBUILD them whenever a
  // generation control changes (debounced for the smooth slider). Each SDF
  // is recomputed from the stored original file, so pipeline improvements
  // apply to old uploads too. Session-only shapes (too large to persist) are
  // kept as-is.
  useEffect(() => {
    let cancelled = false;
    const timer = setTimeout(() => {
      void (async () => {
        const stored = await loadStoredShapes();
        const defs: ShapeDef[] = [];
        for (const s of stored) {
          try {
            const sdf = await buildShapeSdf(await storedShapeToFile(s));
            defs.push(makeCustomShape(sdf, s.id, s.label));
          } catch (err) {
            console.error('[shapes] rebuild failed for', s.label, err);
          }
        }
        if (cancelled) return;
        const rebuilt = new Set(defs.map((d) => d.id));
        setCustomShapes((prev) => [...defs, ...prev.filter((p) => !rebuilt.has(p.id))]);
      })();
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sdfDetail, sdfSource, shapeSmooth]);

  const selected = EXPERIMENTS.find((e) => e.id === selectedId);
  const parsed = useMemo(() => (selected ? parseShader(selected.source) : null), [selected]);
  // Lint what Pencil will actually receive — the export path downgrades
  // workbench-only directives (@select/@switch/@step) to paste-safe @range.
  const lint = useMemo(
    () => (selected ? lintPencil(downgradePencilDirectives(selected.source)) : []),
    [selected],
  );
  const requiresShape = !!parsed?.system.sdf;

  const [previewScale, setPreviewScale] = useLocalStorage<PreviewScale>('previewScale', 'full');
  const hasGrid = parsed?.schema.some((c) => c.key === 'u_gridSize') ?? false;

  // Presets hook — replaces the old useState<ShaderValues> + localStorage persistence.
  const defaultPresetShape = useMemo(
    () => ({ id: requiresShape ? 'rounded-rect' : 'none', size: 1 }),
    [requiresShape],
  );
  const presetStore = usePresets(
    selectedId ?? '',
    parsed?.defaults ?? {},
    parsed?.schema,
    defaultPresetShape,
  );

  const savedShapeId = presetStore.shape.id;
  const shapeId = isUsableShapeId(savedShapeId, shapes)
    ? savedShapeId
    : requiresShape
      ? 'rounded-rect'
      : 'none';
  const selectedShape: ShapeDef | null =
    shapeId === 'none' ? null : (shapes.find((s) => s.id === shapeId) ?? null);
  const shapeScale = presetStore.shape.size;

  const selectShape = (id: string) => {
    presetStore.setShape({ id, size: shapeScale });
  };

  useEffect(() => {
    if (requiresShape && shapeId === 'none') selectShape('rounded-rect');
  }, [requiresShape, shapeId, selectShape]);

  const onUploadShape = async (file: File) => {
    try {
      const sdf = await buildShapeSdf(file);
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

  const onDeleteShape = (id: string) => {
    setCustomShapes((prev) => prev.filter((s) => s.id !== id));
    if (shapeId === id) selectShape(requiresShape ? 'rounded-rect' : 'none');
    void removeStoredShape(id).catch((err) => console.error('[shape delete]', err));
  };

  // Viewport backdrop color — what shows through behind the (clipped) fill.
  // Workbench-only: in Pencil the equivalent is a layer behind the shape.
  const [viewportBg, setViewportBg] = useLocalStorage('viewportBg', '#0a0a0c');

  // Viewport view mode: the experiment itself, its host SDF, or the chrome
  // env panorama. Debug modes swap only the VIEWPORT shader — settings, lint,
  // and export always follow the experiment.
  const [viewMode, setViewMode] = useTabState<ViewMode>('viewMode', 'fill');
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

  const [sdfBands, setSdfBands] = useLocalStorage('sdfBands', 24);
  const sdfViewValues = useMemo<ShaderValues>(() => ({ u_bands: sdfBands }), [sdfBands]);

  // Workbench-only controls injected into the settings column: the viewport
  // backdrop joins the Environment group (own group on shaders without one).
  const settingsExtras = useMemo(
    () => [
      {
        section: 'Shape',
        position: 'before' as const,
        node: (
          <div key="host-shape" className="flex flex-col gap-3">
            <ShapePicker
              shapes={shapes}
              value={shapeId}
              onSelect={selectShape}
              onUpload={onUploadShape}
              onDelete={onDeleteShape}
              requiresShape={requiresShape}
            />
            {selectedShape && (
              <SliderControl
                label="Size"
                value={shapeScale}
                min={0.25}
                max={2}
                step={0.05}
                unit="×"
                onChange={(size) => presetStore.setShape({ id: shapeId, size })}
                onReset={() => presetStore.setShape({ id: shapeId, size: 1 })}
              />
            )}
          </div>
        ),
      },
      ...((viewMode === 'sdf' || selectedShape?.custom)
        ? [
            {
              section: 'Shape Field',
              position: 'before' as const,
              afterSection: 'Shape',
              node: (
                <div key="shape-field" className="flex flex-col gap-3">
                  <div className="flex gap-1">
                    {(['exact', 'raster'] as const).map((s) => (
                      <button
                        key={s}
                        type="button"
                        title={
                          s === 'exact'
                            ? 'Trace the SVG vector outlines directly (SVG only; others always rasterize)'
                            : 'Rasterize + distance transform'
                        }
                        onClick={() => setSdfSource(s)}
                        className={cn(
                          'flex-1 rounded-md px-2 py-1 text-xs font-medium capitalize transition-colors',
                          sdfSource === s
                            ? 'bg-accent text-accent-foreground'
                            : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
                        )}
                      >
                        {s}
                      </button>
                    ))}
                  </div>
                  <div className="flex gap-1">
                    {[512, 1024, 2048].map((r) => (
                      <button
                        key={r}
                        type="button"
                        onClick={() => setSdfDetail(r)}
                        className={cn(
                          'flex-1 rounded-md px-2 py-1 text-xs font-medium transition-colors',
                          sdfDetail === r
                            ? 'bg-accent text-accent-foreground'
                            : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
                        )}
                      >
                        {r}
                      </button>
                    ))}
                  </div>
                  <p className="text-[10px] leading-snug text-muted-foreground">
                    Source + grid resolution for uploaded shapes. Changing either rebuilds every
                    upload from its original file.
                  </p>
                  <SliderControl
                    label="Expand"
                    value={shapeExpand}
                    min={-20}
                    max={20}
                    step={0.5}
                    unit="px"
                    onChange={setShapeExpand}
                    onReset={() => setShapeExpand(0)}
                  />
                  <SliderControl
                    label="Smooth"
                    value={shapeSmooth}
                    min={0}
                    max={6}
                    step={1}
                    onChange={setShapeSmooth}
                    onReset={() => setShapeSmooth(0)}
                  />
                  {viewMode === 'sdf' && (
                    <SliderControl
                      label="Bands"
                      value={sdfBands}
                      min={4}
                      max={64}
                      step={1}
                      unit="px"
                      onChange={setSdfBands}
                      onReset={() => setSdfBands(24)}
                    />
                  )}
                </div>
              ),
            },
          ]
        : []),
      {
        section: 'Environment',
        node: (
          <div key="viewport-backdrop" className="flex items-center gap-2">
            <input
              type="color"
              value={viewportBg}
              onChange={(e) => setViewportBg(e.target.value)}
              onDoubleClick={() => setViewportBg('#0a0a0c')}
              title="Double-click to reset"
              aria-label="Viewport background color"
              className="h-6 w-8 cursor-pointer rounded border border-border bg-transparent p-0"
            />
            <span className="text-[11px]">Background</span>
            <span className="ml-auto text-[10px] text-muted-foreground">preview only</span>
          </div>
        ),
      },
    ],
    [
      onDeleteShape,
      onUploadShape,
      presetStore,
      requiresShape,
      sdfBands,
      sdfDetail,
      sdfSource,
      selectShape,
      selectedShape,
      setSdfBands,
      setSdfDetail,
      setSdfSource,
      setShapeExpand,
      setShapeSmooth,
      setViewportBg,
      shapeExpand,
      shapeId,
      shapeScale,
      shapeSmooth,
      shapes,
      viewMode,
      viewportBg,
    ],
  );

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

  const viewModeButtons = (className?: string) => (
    <div className={cn('flex rounded-md border border-border p-0.5', className)}>
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
  );

  return (
    <div className="flex h-[100dvh] flex-col bg-background text-foreground">
      <header className="shrink-0 border-b border-border">
        <div className="flex h-11 items-center gap-2 px-2 md:h-10 md:gap-3 md:px-4">
          <span className="logo hidden lg:inline">shaders</span>
          <div className="min-w-0 flex-1 md:w-48 md:flex-none">
            <Select value={selectedId} onValueChange={setSelectedId}>
              <SelectTrigger aria-label="Select shader">
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
          <div className="hidden lg:block">
            <FpsPanel
              visible={fpsVisible}
              logging={fpsLogging}
              onToggleVisible={() => setFpsVisible((v) => !v)}
              onToggleLogging={() => setFpsLogging((v) => !v)}
            />
          </div>
          <div className="hidden md:block">
            <UndoRedoButtons
              canUndo={presetStore.canUndo}
              canRedo={presetStore.canRedo}
              onUndo={presetStore.undo}
              onRedo={presetStore.redo}
            />
          </div>
          <div className="hidden md:block">{selected && <LintBadge findings={lint} />}</div>
          <div className="hidden md:block">
            {selected && (canSdfView || canEnvView) && viewModeButtons()}
          </div>

          <div className="ml-auto flex shrink-0 items-center gap-1 md:gap-2">
            {selected && (
              <Button
                variant="ghost"
                size="icon"
                aria-label={running ? 'Pause' : 'Play'}
                title={running ? 'Pause (Space)' : 'Play (Space)'}
                onClick={() => setRunning((r) => !r)}
                className="md:hidden"
              >
                {running ? <Pause /> : <Play />}
              </Button>
            )}
            {parsed && (
              <Button
                variant="ghost"
                size="icon"
                aria-label={settingsOpen ? 'Hide settings' : 'Show settings'}
                aria-pressed={settingsOpen}
                title={settingsOpen ? 'Hide settings' : 'Show settings'}
                onClick={() => setSettingsOpen((open) => !open)}
              >
                {settingsOpen ? <PanelRightClose /> : <PanelRightOpen />}
              </Button>
            )}
            {selected && (
              <Button
                variant="ghost"
                size="icon"
                aria-label="Copy for Pencil"
                title="Copy for Pencil (current values baked into @default)"
                onClick={copyGlsl}
                className="hidden md:inline-flex"
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
                className="hidden md:inline-flex"
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
                className="hidden md:inline-flex"
              >
                {running ? <Pause /> : <Play />}
              </Button>
            )}
            {selected && (
              <DropdownMenu modal={false}>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon"
                    aria-label="More actions"
                    title="More actions"
                    className="md:hidden"
                  >
                    <MoreHorizontal />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-48">
                  <DropdownMenuItem onClick={() => void copyGlsl()}>
                    {copied ? <Check /> : <ClipboardCopy />}
                    {copied ? 'Copied for Pencil' : 'Copy for Pencil'}
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={downloadGlsl}>
                    <Download /> Download .glsl
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={() => setFpsVisible((v) => !v)}>
                    {fpsVisible ? 'Hide' : 'Show'} FPS on desktop
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => setFpsLogging((v) => !v)}>
                    {fpsLogging ? 'Stop' : 'Start'} performance logging
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        </div>

        {selected && (
          <div className="flex h-9 items-center gap-1 border-t border-border px-2 md:hidden">
            <UndoRedoButtons
              canUndo={presetStore.canUndo}
              canRedo={presetStore.canRedo}
              onUndo={presetStore.undo}
              onRedo={presetStore.redo}
            />
            <div className="min-w-0 flex-1">
              {(canSdfView || canEnvView) && viewModeButtons('w-fit')}
            </div>
            <LintBadge findings={lint} />
          </div>
        )}
      </header>

      <div className="relative flex min-h-0 flex-1">
        <main className="flex min-w-0 flex-1 items-center justify-center overflow-hidden p-6">
          {selected && parsed && viewParsed && viewSource ? (
            <div
              className="h-full w-full overflow-hidden rounded-lg border border-border"
              style={{ background: viewportBg }}
            >
              <ErrorBoundary key={`${selected.id}:${viewMode}`} label="Viewport crashed">
                <ShaderViewport
                  parsed={viewParsed}
                  fragSource={viewSource}
                  values={viewMode === 'sdf' ? sdfViewValues : presetStore.values}
                  running={running}
                  shape={viewMode === 'env' ? null : selectedShape}
                  shapeScale={shapeScale}
                  shapeExpand={shapeExpand}
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
              open={settingsOpen}
              onClose={() => setSettingsOpen(false)}
              storageKey={selectedId}
              schema={parsed.schema}
              value={presetStore.values}
              defaults={parsed.defaults}
              onChange={onChange}
              pencilKeys={presetStore.pencilKeys}
              onTogglePencil={presetStore.togglePencilKey}
              extras={settingsExtras}
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
