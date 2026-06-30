import { Switch } from '@/components/ui/switch';
import { ResetLabel } from './field';

export function SwitchControl({
  label,
  hint,
  value,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: boolean;
  onChange: (v: boolean) => void;
  onReset?: () => void;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between gap-2">
        <ResetLabel label={label} onReset={onReset} />
        <Switch checked={value} onCheckedChange={onChange} />
      </div>
      {hint && <p className="text-[10px] leading-tight text-muted-foreground/50">{hint}</p>}
    </div>
  );
}
