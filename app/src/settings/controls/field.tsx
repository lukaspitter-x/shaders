import type { ReactNode } from 'react';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/cn';

/**
 * Shared control layout: a label row (with optional inline value/aux on the
 * right) above the control body, plus an optional hint line.
 *
 * When `onReset` is provided the label becomes a button that resets the
 * control to its default value on click.
 */
export function Field({
  label,
  hint,
  aux,
  onReset,
  children,
  className,
}: {
  label: string;
  hint?: string;
  aux?: ReactNode;
  onReset?: () => void;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <div className="flex items-center justify-between gap-2">
        <ResetLabel label={label} onReset={onReset} />
        {aux != null && <span className="text-[11px] tabular-nums text-muted-foreground/70">{aux}</span>}
      </div>
      {children}
      {hint && <p className="text-[10px] leading-tight text-muted-foreground/50">{hint}</p>}
    </div>
  );
}

/** The label, rendered as a reset button when `onReset` is given. */
export function ResetLabel({
  label,
  onReset,
  className,
}: {
  label: string;
  onReset?: () => void;
  className?: string;
}) {
  if (!onReset) return <Label className={cn('text-muted-foreground', className)}>{label}</Label>;
  return (
    <button
      type="button"
      onClick={onReset}
      title="Reset to default"
      className={cn(
        'text-left text-xs font-medium text-muted-foreground outline-none transition-colors hover:text-foreground',
        className,
      )}
    >
      {label}
    </button>
  );
}
