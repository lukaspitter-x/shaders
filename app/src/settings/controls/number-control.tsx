import { NumberField } from './number-field';
import { Field } from './field';

export function NumberControl({
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
  min?: number;
  max?: number;
  step?: number;
  unit?: string;
  onChange: (v: number) => void;
  onReset?: () => void;
}) {
  return (
    <Field label={label} hint={hint} onReset={onReset}>
      <div className="flex items-center gap-1">
        <NumberField
          value={value}
          min={min}
          max={max}
          step={step}
          onChange={onChange}
          className="tabular-nums"
        />
        {unit && <span className="text-[10px] text-muted-foreground/60">{unit}</span>}
      </div>
    </Field>
  );
}
