import { Input } from '@/components/ui/input';
import { Field } from './field';

export function TextControl({
  label,
  hint,
  value,
  placeholder,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: string;
  placeholder?: string;
  onChange: (v: string) => void;
  onReset?: () => void;
}) {
  return (
    <Field label={label} hint={hint} onReset={onReset}>
      <Input value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
    </Field>
  );
}
