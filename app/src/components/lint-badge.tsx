import { CircleCheck, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { cn } from '@/lib/cn';
import type { LintFinding } from '@/glsl/lint-pencil';

/**
 * Pencil-compatibility badge: shows whether the authored shader stays inside
 * Pencil's GLSL ES 1.00 envelope (the preview is WebGL2, a superset). Green when
 * clean; otherwise a count that opens the list of findings. Driven by props.
 */
export function LintBadge({ findings }: { findings: LintFinding[] }) {
  const errors = findings.filter((f) => f.severity === 'error').length;
  const warnings = findings.length - errors;
  const clean = findings.length === 0;

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="sm"
          className={cn('h-8 gap-1.5', errors > 0 && 'text-destructive')}
          title="Pencil compatibility"
          aria-label="Pencil compatibility"
        >
          {clean ? <CircleCheck className="h-4 w-4" /> : <TriangleAlert className="h-4 w-4" />}
          <span className="text-[11px] tabular-nums">
            {clean ? 'Pencil' : `${errors ? `${errors}✕` : ''}${errors && warnings ? ' ' : ''}${warnings ? `${warnings}!` : ''}`}
          </span>
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-[calc(100vw-1rem)] max-w-[340px] p-0">
        <div className="border-b border-border px-3 py-2">
          <p className="heading">Pencil compatibility</p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {clean
              ? 'Stays within Pencil’s GLSL ES 1.00 envelope.'
              : 'The preview is WebGL2; these would fail or misbehave on paste into Pencil.'}
          </p>
        </div>
        {clean ? (
          <div className="px-3 py-3 text-[11px] text-muted-foreground">No issues found.</div>
        ) : (
          <ul className="max-h-[320px] overflow-auto py-1">
            {findings.map((f, i) => (
              <li key={i} className="flex gap-2 px-3 py-1.5">
                <span
                  className={cn(
                    'mt-0.5 select-none text-[10px] font-medium tabular-nums',
                    f.severity === 'error' ? 'text-destructive' : 'text-muted-foreground',
                  )}
                  title={f.severity}
                >
                  L{f.line}
                </span>
                <div className="min-w-0">
                  <p className="text-[11px] leading-snug text-foreground">{f.message}</p>
                  {f.suggestion && (
                    <p className="text-[10px] leading-snug text-muted-foreground/70">
                      {f.suggestion}
                    </p>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </PopoverContent>
    </Popover>
  );
}
