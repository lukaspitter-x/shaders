import { NumberField } from './number-field';
import { ResetLabel } from './field';

export type Vec3 = [number, number, number];

const AXES = ['X', 'Y', 'Z'] as const;

/** Compact 3-axis control: label + three small X/Y/Z fields on one line. */
export function Vec3Control({
  label,
  hint,
  value,
  min,
  max,
  step = 1,
  unit,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: Vec3;
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  onChange: (v: Vec3) => void;
  onReset?: () => void;
}) {
  const decimals = step < 1 ? Math.min(3, String(step).split('.')[1]?.length ?? 0) : 0;
  const set = (i: number, v: number) => {
    const next = [...value] as Vec3;
    next[i] = v;
    onChange(next);
  };

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center gap-2">
        <ResetLabel label={label} onReset={onReset} className="w-14 shrink-0" />
        <div className="flex flex-1 gap-1">
          {AXES.map((ax, i) => (
            <div key={ax} className="relative flex-1">
              <span className="pointer-events-none absolute left-1 top-1/2 -translate-y-1/2 text-[9px] font-medium text-muted-foreground/40">
                {ax}
              </span>
              <NumberField
                value={value[i]}
                min={min}
                max={max}
                step={step}
                decimals={decimals}
                onChange={(v) => set(i, v)}
                className="h-6 pl-3 pr-1 text-right text-[11px] tabular-nums"
              />
            </div>
          ))}
        </div>
        {unit && <span className="text-[10px] text-muted-foreground/60">{unit}</span>}
      </div>
      {hint && <p className="text-[10px] leading-tight text-muted-foreground/50">{hint}</p>}
    </div>
  );
}
