import { useState } from 'react';
import { Input } from '@/components/ui/input';

/**
 * A numeric text field that doesn't fight what you type.
 *
 * The bug it fixes: a fully-controlled `<input type=number value={value}>` that
 * parses + clamps + writes back to the store on every keystroke reformats the
 * field mid-type — so a trailing ".", a value briefly below `min`, or clearing
 * the field gets stomped and the caret jumps. Here we keep the raw text in a
 * local `draft` while focused and only show the prop value once focus leaves.
 * Edits still preview live (we call `onChange` whenever the draft parses), but
 * the *displayed* string is always exactly what the user typed until blur.
 */
export function NumberField({
  value,
  min,
  max,
  step,
  decimals,
  onChange,
  className,
  onFocus,
  onBlur,
  onKeyDown,
  ...rest
}: {
  value: number;
  min?: number;
  max?: number;
  step?: number;
  /** Decimal places used to format the value when NOT focused. */
  decimals?: number;
  onChange: (v: number) => void;
} & Omit<
  React.ComponentProps<typeof Input>,
  'value' | 'onChange' | 'type' | 'min' | 'max' | 'step'
>) {
  const [draft, setDraft] = useState<string | null>(null);

  const clamp = (v: number) => {
    let n = v;
    if (min !== undefined) n = Math.max(min, n);
    if (max !== undefined) n = Math.min(max, n);
    return n;
  };

  const formatted =
    decimals !== undefined && Number.isFinite(value)
      ? String(Number(value.toFixed(decimals)))
      : String(value);

  // While editing, show the user's raw text; otherwise the (clamped) prop value.
  const shown = draft ?? formatted;

  return (
    <Input
      {...rest}
      type="text"
      inputMode="decimal"
      value={shown}
      className={className}
      onWheel={(e) => e.currentTarget.blur()}
      onFocus={(e) => {
        setDraft(formatted);
        e.currentTarget.select();
        onFocus?.(e);
      }}
      onChange={(e) => {
        const raw = e.target.value;
        setDraft(raw);
        // Preview live only when the text is a complete number; intermediate
        // states ("", "-", "1.", ".") leave the last committed value in place.
        const v = parseFloat(raw);
        if (raw.trim() !== '' && !Number.isNaN(v) && Number.isFinite(v) && /\d$/.test(raw.trim())) {
          onChange(clamp(v));
        }
      }}
      onBlur={(e) => {
        const v = parseFloat(e.target.value);
        if (!Number.isNaN(v) && Number.isFinite(v)) onChange(clamp(v));
        setDraft(null); // re-sync the display to the committed prop value
        onBlur?.(e);
      }}
      onKeyDown={(e) => {
        if (e.key === 'Enter') {
          e.currentTarget.blur();
        } else if (step && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
          // Preserve the spinner ergonomics lost by dropping type="number".
          e.preventDefault();
          const dir = e.key === 'ArrowUp' ? 1 : -1;
          const next = clamp(value + dir * step * (e.shiftKey ? 10 : 1));
          setDraft(String(Number(next.toFixed(decimals ?? 6))));
          onChange(next);
        }
        onKeyDown?.(e);
      }}
    />
  );
}
