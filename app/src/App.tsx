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

const isUsableShapeId = (id: string | null): id is string =>
  id === 'none' || BUILTIN_SHAPES.some((s) => s.id === id);

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
  const shapes = useMemo(() => [...BUILTIN_SHAPES, ...customShapes], [customShapes]);

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

  // Restore shape on shader switch.
  useEffect(() => {
    if (!parsed || !selected) {
      setShapeId('none');
      return;
    }
    const storedShape = readJson<string | null>(shapeKey(selected.id), null);
    setShapeId(
      isUsableShapeId(storedShape)
        ? storedShape
        : parsed.system.sdf
          ? 'rounded-rect'
          : 'none',
    );
  }, [parsed, selected]);

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
      const label = file.name.replace(/\.[^.]+$/, '') || 'Custom';
      setCustomShapes((prev) => [...prev, makeCustomShape(sdf, id, label)]);
      setShapeId(id);
    } catch (err) {
      console.error('[shape upload]', err);
    }
  };

  const onChange = (key: string, value: ShaderValues[string]) => {
    presetStore.setValue(key, value);
  };

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
          {selected && parsed ? (
            <div className="h-full w-full overflow-hidden rounded-lg border border-border">
              <ErrorBoundary key={selected.id} label="Viewport crashed">
                <ShaderViewport
                  parsed={parsed}
                  fragSource={selected.source}
                  values={presetStore.values}
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
