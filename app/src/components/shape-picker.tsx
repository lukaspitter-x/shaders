import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Upload } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/cn';
import { drawShapeThumbnail, type ShapeDef } from '@/render/sdf-shapes';

/** Canvas silhouette of a shape (or a filled tile for `null` = full background). */
function ShapeThumb({ shape, size }: { shape: ShapeDef | null; size: number }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    if (ref.current) drawShapeThumbnail(ref.current, shape, size);
  }, [shape, size]);
  return (
    <canvas
      ref={ref}
      className="rounded-sm bg-secondary/40"
      style={{ width: size, height: size }}
    />
  );
}

/**
 * Host-shape picker: a popover of shape thumbnails (built-ins + uploads) plus a
 * "None / full background" tile and an upload tile. `value` is a shape id, or
 * `'none'`. Uploads call `onUpload(file)` — the parent derives the SDF.
 */
export function ShapePicker({
  shapes,
  value,
  onSelect,
  onUpload,
}: {
  shapes: ShapeDef[];
  value: string;
  onSelect: (id: string) => void;
  onUpload: (file: File) => void;
}) {
  const [open, setOpen] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const current = value === 'none' ? null : (shapes.find((s) => s.id === value) ?? null);
  const currentLabel = value === 'none' ? 'None' : (current?.label ?? 'None');

  const tiles: { id: string; label: string; def: ShapeDef | null }[] = [
    { id: 'none', label: 'None', def: null },
    ...shapes.map((s) => ({ id: s.id, label: s.label, def: s })),
  ];

  const onFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    if (f) onUpload(f);
    e.target.value = '';
    setOpen(false);
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="outline" size="sm" className="h-8 gap-2">
          <ShapeThumb shape={current} size={18} />
          <span className="max-w-[90px] truncate">{currentLabel}</span>
          <ChevronDown className="h-3.5 w-3.5 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-[264px] p-2">
        <div className="grid grid-cols-3 gap-2">
          {tiles.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => {
                onSelect(t.id);
                setOpen(false);
              }}
              className={cn(
                'flex flex-col items-center gap-1 rounded-md border p-2 outline-none transition-colors hover:bg-accent',
                t.id === value ? 'border-foreground/40 bg-accent' : 'border-border',
              )}
            >
              <ShapeThumb shape={t.def} size={40} />
              <span className="w-full truncate text-center text-[10px] text-muted-foreground">
                {t.label}
              </span>
            </button>
          ))}
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="flex flex-col items-center justify-center gap-1 rounded-md border border-dashed border-border p-2 text-muted-foreground outline-none transition-colors hover:bg-accent hover:text-foreground"
          >
            <Upload className="h-5 w-5" />
            <span className="text-[10px]">Upload</span>
          </button>
        </div>
        <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={onFile} />
      </PopoverContent>
    </Popover>
  );
}
