import { useCallback, useRef } from 'react';
import { Field } from './field';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export type Bezier = [number, number, number, number];

/** Cubic-bezier presets for the settings control dropdown. */
const BEZIER_PRESETS: { value: string; label: string; curve: Bezier }[] = [
  { value: 'linear', label: 'Linear', curve: [0, 0, 1, 1] },
  { value: 'ease', label: 'Ease', curve: [0.25, 0.1, 0.25, 1] },
  { value: 'easeIn', label: 'Ease In', curve: [0.42, 0, 1, 1] },
  { value: 'easeOut', label: 'Ease Out', curve: [0, 0, 0.58, 1] },
  { value: 'easeInOut', label: 'Ease In Out', curve: [0.42, 0, 0.58, 1] },
  { value: 'expoOut', label: 'Expo Out', curve: [0.16, 1, 0.3, 1] },
  { value: 'backOut', label: 'Back Out', curve: [0.34, 1.56, 0.64, 1] },
];

function matchPreset(c: Bezier): string {
  const hit = BEZIER_PRESETS.find((p) => p.curve.every((v, i) => Math.abs(v - c[i]) < 0.001));
  return hit?.value ?? 'custom';
}

// Curve space: x ∈ [0,1]; y may overshoot [0,1] (back/elastic feels). The
// drawing area spans a wider Y band than the unit box and keeps a generous PAD,
// so the control handles stay inside the clickable SVG even at the extremes.
const PAD = 18;
const W = 176; // drawing width (one x-unit)
const Y_MIN = -0.6;
const Y_MAX = 1.6;
const Y_SPAN = Y_MAX - Y_MIN; // visible == clamped y range, so handles never leave
const H = 240; // drawing height for the full y span
const SVG_W = W + PAD * 2;
const SVG_H = H + PAD * 2;

/**
 * Cubic-bezier easing editor: an SVG curve with two draggable control points
 * plus a preset dropdown. Y is allowed to overshoot [0,1] (for back/elastic
 * feels); X is clamped to [0,1] as required by CSS cubic-bezier.
 */
export function BezierControl({
  label,
  hint,
  value,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: Bezier;
  onChange: (v: Bezier) => void;
  onReset?: () => void;
}) {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const dragRef = useRef<0 | 1 | null>(null);

  // Map curve space (x:[0,1]; y in [Y_MIN,Y_MAX], bottom-up) → svg px.
  const toPx = (x: number, y: number) => ({
    x: PAD + x * W,
    y: PAD + ((Y_MAX - y) / Y_SPAN) * H,
  });
  const p1 = toPx(value[0], value[1]);
  const p2 = toPx(value[2], value[3]);
  const start = toPx(0, 0);
  const end = toPx(1, 1);
  const boxTL = toPx(0, 1); // unit-box top-left
  const boxBR = toPx(1, 0); // unit-box bottom-right

  const onMove = useCallback(
    (e: PointerEvent | React.PointerEvent) => {
      const which = dragRef.current;
      if (which === null) return;
      const svg = svgRef.current;
      if (!svg) return;
      const r = svg.getBoundingClientRect();
      // The svg scales uniformly to its rendered width, so convert client px →
      // viewBox units before un-mapping (else dragging is off by the scale).
      const sx = r.width / SVG_W;
      const sy = r.height / SVG_H;
      const cx = 'clientX' in e ? e.clientX : 0;
      const cy = 'clientY' in e ? e.clientY : 0;
      const px = ((cx - r.left) / sx - PAD) / W;
      const py = Y_MAX - (((cy - r.top) / sy - PAD) / H) * Y_SPAN;
      const x = Math.max(0, Math.min(1, px));
      const y = Math.max(Y_MIN, Math.min(Y_MAX, py));
      const next: Bezier = [...value];
      next[which * 2] = Math.round(x * 1000) / 1000;
      next[which * 2 + 1] = Math.round(y * 1000) / 1000;
      onChange(next);
    },
    [value, onChange],
  );

  const startDrag = (which: 0 | 1) => (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    dragRef.current = which;
    const move = (ev: PointerEvent) => onMove(ev);
    const up = () => {
      dragRef.current = null;
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  const preset = matchPreset(value);

  return (
    <Field
      label={label}
      hint={hint}
      onReset={onReset}
      aux={`${value.map((v) => v.toFixed(2)).join(', ')}`}
    >
      <div className="flex flex-col gap-2">
        <Select
          value={preset}
          onValueChange={(v) => {
            const p = BEZIER_PRESETS.find((x) => x.value === v);
            if (p) onChange([...p.curve]);
          }}
        >
          <SelectTrigger>
            <SelectValue placeholder="Custom" />
          </SelectTrigger>
          <SelectContent>
            {preset === 'custom' && (
              <SelectItem value="custom" disabled>
                Custom
              </SelectItem>
            )}
            {BEZIER_PRESETS.map((p) => (
              <SelectItem key={p.value} value={p.value}>
                {p.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>

        <svg
          ref={svgRef}
          width="100%"
          viewBox={`0 0 ${SVG_W} ${SVG_H}`}
          className="touch-none rounded-md border border-border bg-secondary/30"
        >
          {/* unit box (the [0,1] range; the area above/below is overshoot room) */}
          <rect
            x={boxTL.x}
            y={boxTL.y}
            width={boxBR.x - boxTL.x}
            height={boxBR.y - boxTL.y}
            fill="none"
            stroke="hsl(var(--border))"
            strokeDasharray="2 3"
          />
          {/* handles */}
          <line x1={start.x} y1={start.y} x2={p1.x} y2={p1.y} stroke="hsl(var(--muted-foreground))" strokeOpacity={0.5} />
          <line x1={end.x} y1={end.y} x2={p2.x} y2={p2.y} stroke="hsl(var(--muted-foreground))" strokeOpacity={0.5} />
          {/* curve */}
          <path
            d={`M ${start.x} ${start.y} C ${p1.x} ${p1.y}, ${p2.x} ${p2.y}, ${end.x} ${end.y}`}
            fill="none"
            stroke="hsl(var(--foreground))"
            strokeWidth={2}
          />
          {/* endpoints */}
          <circle cx={start.x} cy={start.y} r={3} fill="hsl(var(--muted-foreground))" />
          <circle cx={end.x} cy={end.y} r={3} fill="hsl(var(--muted-foreground))" />
          {/* draggable control points (transparent hit target + visible dot) */}
          <circle
            cx={p1.x}
            cy={p1.y}
            r={13}
            fill="transparent"
            className="cursor-grab active:cursor-grabbing"
            onPointerDown={startDrag(0)}
          />
          <circle cx={p1.x} cy={p1.y} r={6} fill="hsl(var(--primary))" className="pointer-events-none" />
          <circle
            cx={p2.x}
            cy={p2.y}
            r={13}
            fill="transparent"
            className="cursor-grab active:cursor-grabbing"
            onPointerDown={startDrag(1)}
          />
          <circle cx={p2.x} cy={p2.y} r={6} fill="hsl(var(--primary))" className="pointer-events-none" />
        </svg>
      </div>
    </Field>
  );
}
