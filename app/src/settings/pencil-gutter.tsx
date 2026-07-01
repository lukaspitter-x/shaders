import type { ReactNode } from 'react';
import { Square, SquareCheck } from 'lucide-react';
import { cn } from '@/lib/cn';

export function PencilGutter({
  checked,
  onToggle,
  align = 'top',
  children,
}: {
  checked: boolean;
  onToggle: () => void;
  align?: 'top' | 'center';
  children: ReactNode;
}) {
  const offset = align === 'center' ? 'mt-2' : 'mt-0';

  return (
    <div className="flex items-start gap-1">
      <button
        type="button"
        onClick={onToggle}
        aria-label={checked ? 'Hide in Pencil' : 'Show in Pencil'}
        aria-pressed={checked}
        title={checked ? 'Visible in Pencil — click to hide' : 'Hidden from Pencil — click to show'}
        className={cn(
          offset,
          'shrink-0 rounded p-0.5 outline-none transition-colors',
          checked
            ? 'text-primary'
            : 'text-muted-foreground/25 hover:text-muted-foreground',
        )}
      >
        {checked ? (
          <SquareCheck className="h-3 w-3" />
        ) : (
          <Square className="h-3 w-3" />
        )}
      </button>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
