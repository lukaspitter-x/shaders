import { useRef } from 'react';
import { cn } from '@/lib/cn';
import { NumberField } from './number-field';
import { ResetLabel } from './field';

/**
 * lil-gui–style fill-row slider with a dedicated number field to its right.
 * The track fill *is* the value level (no knob); drag anywhere on the track to
 * scrub. The number input lives OUTSIDE the track, so typing an exact value
 * never starts a scrub. The label sits on the track (click to reset).
 */
export function SliderControl({
  label,
  hint,
  value,
  min,
  max,
  step,
  unit,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit?: string;
  onChange: (v: number) => void;
  onReset?: () => void;
}) {
  const trackRef = useRef<HTMLDivElement>(null);

  const decimals = step < 1 ? Math.min(3, String(step).split('.')[1]?.length ?? 0) : 0;
  const clamp = (v: number) => Math.max(min, Math.min(max, v));
  const snap = (v: number) => clamp(Math.round(v / step) * step);
  const pct = max > min ? ((clamp(value) - min) / (max - min)) * 100 : 0;

  function valueFromClientX(clientX: number) {
    const el = trackRef.current;
    if (!el) return value;
    const r = el.getBoundingClientRect();
    const t = r.width > 0 ? (clientX - r.left) / r.width : 0;
    return snap(min + t * (max - min));
  }

  function onPointerDown(e: React.PointerEvent) {
    if (e.button !== 0) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    onChange(valueFromClientX(e.clientX));
  }

  // Pointer is captured on the track, so moves route here; gate on the primary
  // button still being held so plain hovers don't scrub.
  function onPointerMove(e: React.PointerEvent) {
    if ((e.buttons & 1) === 0) return;
    onChange(valueFromClientX(e.clientX));
  }

  function onKeyDown(e: React.KeyboardEvent) {
    const dir =
      e.key === 'ArrowRight' || e.key === 'ArrowUp'
        ? 1
        : e.key === 'ArrowLeft' || e.key === 'ArrowDown'
          ? -1
          : 0;
    if (!dir) return;
    e.preventDefault();
    onChange(snap(value + dir * step * (e.shiftKey ? 10 : 1)));
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center gap-1.5">
        <div
          ref={trackRef}
          role="slider"
          tabIndex={0}
          aria-label={label}
          aria-valuenow={value}
          aria-valuemin={min}
          aria-valuemax={max}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onKeyDown={onKeyDown}
          className={cn(
            'relative flex h-8 flex-1 touch-none select-none items-center overflow-hidden rounded-md',
            'cursor-ew-resize bg-secondary text-xs transition-colors hover:bg-secondary/80',
            'outline-none focus-visible:ring-1 focus-visible:ring-ring',
          )}
        >
          {/* Fill = level. A foreground tint over the track works in both themes. */}
          <div
            className="pointer-events-none absolute inset-y-0 left-0 bg-foreground/10"
            style={{ width: `${pct}%` }}
          />
          {/* Reset island: clicking the label resets and must not scrub. */}
          <span className="relative z-10 px-2" onPointerDown={(e) => e.stopPropagation()}>
            <ResetLabel label={label} onReset={onReset} className="text-[11px]" />
          </span>
        </div>

        {/* Number field lives OUTSIDE the track — typing never scrubs. */}
        <div className="flex w-16 shrink-0 items-center gap-0.5">
          <NumberField
            value={value}
            min={min}
            max={max}
            step={step}
            decimals={decimals}
            onChange={(v) => onChange(clamp(v))}
            className="h-8 px-1.5 text-right text-[11px] tabular-nums"
          />
          {unit && <span className="text-[10px] text-muted-foreground/60">{unit}</span>}
        </div>
      </div>
      {hint && <p className="text-[10px] leading-tight text-muted-foreground/50">{hint}</p>}
    </div>
  );
}
