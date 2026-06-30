import { useRef } from 'react';
import { ImagePlus, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Field } from './field';

export function ImageControl({
  label,
  hint,
  value,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: string;
  onChange: (v: string) => void;
  onReset?: () => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);

  const onFile = (file: File) => {
    if (!file.type.startsWith('image/')) return;
    const url = URL.createObjectURL(file);
    if (value) URL.revokeObjectURL(value);
    onChange(url);
  };

  const onClear = () => {
    if (value) URL.revokeObjectURL(value);
    onChange('');
  };

  return (
    <Field label={label} hint={hint} onReset={onReset}>
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) onFile(f);
          e.target.value = '';
        }}
      />
      {value ? (
        <div className="group relative">
          <img
            src={value}
            alt={label}
            className="h-20 w-full rounded-md border border-input object-cover"
          />
          <div className="absolute inset-x-0 bottom-0 flex gap-1 rounded-b-md bg-background/80 p-1 opacity-0 transition-opacity group-hover:opacity-100">
            <Button
              variant="ghost"
              size="sm"
              className="h-6 flex-1 text-[10px]"
              onClick={() => inputRef.current?.click()}
            >
              Replace
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={onClear}
            >
              <X className="h-3 w-3" />
            </Button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex h-20 w-full items-center justify-center gap-2 rounded-md border border-dashed border-input text-[11px] text-muted-foreground transition-colors hover:border-foreground/30 hover:text-foreground"
        >
          <ImagePlus className="h-4 w-4" />
          Choose image
        </button>
      )}
    </Field>
  );
}
