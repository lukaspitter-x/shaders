import { useCallback, useEffect, useRef, useState } from 'react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Input } from '@/components/ui/input';
import { Field } from './field';
import { hexToHsv, hsvToHex, normalizeHex } from '@/lib/hex';
import { cn } from '@/lib/cn';

const PRESETS = [
  '#000000',
  '#ffffff',
  '#0a0a0a',
  '#1a1a1a',
  '#f5f5f5',
  '#165deb',
  '#12bff3',
  '#ed5c0e',
  '#0eed94',
  '#ed0e42',
];

/** Drag-to-pick HSV square + hue slider + hex input + preset swatches. */
export function ColorControl({
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
  const hsv = hexToHsv(value);
  const [hex, setHex] = useState(value);
  useEffect(() => setHex(value), [value]);

  const svRef = useRef<HTMLDivElement | null>(null);

  const pickSV = useCallback(
    (clientX: number, clientY: number) => {
      const el = svRef.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const s = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
      const v = Math.max(0, Math.min(1, 1 - (clientY - r.top) / r.height));
      onChange(hsvToHex(hsv.h, s, v));
    },
    [hsv.h, onChange],
  );

  const onSVPointerDown = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    pickSV(e.clientX, e.clientY);
  };
  const onSVPointerMove = (e: React.PointerEvent) => {
    if (e.buttons !== 1) return;
    pickSV(e.clientX, e.clientY);
  };

  const commitHex = () => {
    const norm = normalizeHex(hex);
    if (norm) onChange(norm);
    else setHex(value);
  };

  return (
    <Field label={label} hint={hint} onReset={onReset}>
      <Popover>
        <div className="flex items-center gap-2">
          <PopoverTrigger asChild>
            <button
              type="button"
              aria-label={`${label} color`}
              className="h-7 w-9 shrink-0 rounded-md border border-input shadow-sm"
              style={{ backgroundColor: value }}
            />
          </PopoverTrigger>
          <Input
            value={hex}
            spellCheck={false}
            onChange={(e) => setHex(e.target.value)}
            onBlur={commitHex}
            onKeyDown={(e) => e.key === 'Enter' && commitHex()}
            className="font-mono lowercase"
          />
        </div>
        <PopoverContent className="w-56" align="start">
          <div
            ref={svRef}
            onPointerDown={onSVPointerDown}
            onPointerMove={onSVPointerMove}
            className="relative h-32 w-full cursor-crosshair rounded-md"
            style={{
              backgroundColor: hsvToHex(hsv.h, 1, 1),
              backgroundImage:
                'linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, transparent)',
            }}
          >
            <div
              className="pointer-events-none absolute h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow"
              style={{ left: `${hsv.s * 100}%`, top: `${(1 - hsv.v) * 100}%` }}
            />
          </div>

          <input
            type="range"
            min={0}
            max={359}
            value={Math.round(hsv.h)}
            onChange={(e) => onChange(hsvToHex(parseInt(e.target.value, 10), hsv.s, hsv.v))}
            className="mt-3 h-3 w-full cursor-pointer appearance-none rounded-full [&::-webkit-slider-thumb]:h-3 [&::-webkit-slider-thumb]:w-3 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-white [&::-webkit-slider-thumb]:bg-transparent"
            style={{
              background:
                'linear-gradient(to right,#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00)',
            }}
          />

          <div className="mt-3 grid grid-cols-10 gap-1">
            {PRESETS.map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => onChange(p)}
                className={cn(
                  'h-4 w-full rounded-sm border border-border',
                  p.toLowerCase() === value.toLowerCase() && 'ring-1 ring-ring',
                )}
                style={{ backgroundColor: p }}
              />
            ))}
          </div>
        </PopoverContent>
      </Popover>
    </Field>
  );
}
