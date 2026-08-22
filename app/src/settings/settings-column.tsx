import { Fragment, useState, type ReactNode } from 'react';
import { ChevronDown, X } from 'lucide-react';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import { cn } from '@/lib/cn';
import type { SettingsSchema } from './schema';
import { ControlRenderer } from './control-renderer';
import { PencilGutter } from './pencil-gutter';

// Collapse state is per-browser editor chrome (not session-preset values), so
// it lives in localStorage keyed by experiment id — never the git-tracked
// sessions.json. Sections default to open when there's no stored entry.
const OPEN_PREFIX = 'bf:sections:';

function loadOpenMap(key: string | undefined): Record<string, boolean> {
  if (!key) return {};
  try {
    const raw = localStorage.getItem(OPEN_PREFIX + key);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function saveOpenMap(key: string | undefined, map: Record<string, boolean>): void {
  if (!key) return;
  try {
    localStorage.setItem(OPEN_PREFIX + key, JSON.stringify(map));
  } catch {
    /* best-effort — collapse memory is a convenience */
  }
}

/** A section header that toggles the visibility of its controls. */
export function CollapsibleSection({
  title,
  open,
  onToggle,
  children,
}: {
  title: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={open}
        className="group -my-0.5 flex items-center justify-between gap-2 outline-none"
      >
        <span className="heading transition-colors group-hover:text-muted-foreground">{title}</span>
        <ChevronDown
          className={cn(
            'h-3 w-3 text-muted-foreground/40 transition-transform group-hover:text-muted-foreground',
            !open && '-rotate-90',
          )}
        />
      </button>
      {open && <div className="flex flex-col gap-3">{children}</div>}
    </div>
  );
}

/**
 * The right "Settings" column. Renders a declarative schema grouped by
 * section (each section collapsible), plus an optional header (e.g. the
 * session switcher) pinned above. Knows nothing about any specific experiment.
 */
export function SettingsColumn<S>({
  schema,
  value,
  defaults,
  onChange,
  header,
  title,
  storageKey,
  open = true,
  onClose,
  pencilKeys,
  onTogglePencil,
  extras,
}: {
  schema: SettingsSchema<S>;
  value: S;
  /** Defaults for each key; clicking a control's label resets it. */
  defaults: S;
  onChange: <K extends keyof S>(key: K, value: S[K]) => void;
  header?: ReactNode;
  title?: string;
  /** Namespace (e.g. experiment id) for remembering section collapse state. */
  storageKey?: string;
  /** When false the panel is collapsed (desktop) / slid off-screen (mobile). */
  open?: boolean;
  /** Dismiss handler for the mobile drawer's close button. */
  onClose?: () => void;
  /** Uniform keys marked as visible in Pencil. */
  pencilKeys?: Set<string>;
  /** Toggle a uniform's Pencil visibility. When provided, each control shows a checkbox gutter. */
  onTogglePencil?: (key: string) => void;
  /**
   * Workbench-level controls appended into a named schema section (e.g. the
   * viewport backdrop into "Environment"). A `before` extra is prepended to
   * its matching section, or becomes a leading group if that section doesn't
   * exist. An orphan with `afterSection` becomes its own group immediately
   * after that schema section. Other orphan extras render at the end.
   */
  extras?: {
    section: string;
    node: ReactNode;
    position?: 'before' | 'after';
    afterSection?: string;
  }[];
}) {
  // Persisted collapse state, keyed per `storageKey`. Default = open.
  const [openMap, setOpenMap] = useState<Record<string, boolean>>(() => loadOpenMap(storageKey));
  const isOpen = (section: string) => openMap[section] ?? true;
  const toggleSection = (section: string) =>
    setOpenMap((prev) => {
      const next = { ...prev, [section]: !(prev[section] ?? true) };
      saveOpenMap(storageKey, next);
      return next;
    });

  // Drop controls hidden for the current settings, then group consecutive
  // controls by section label (so a fully-hidden section's header vanishes too).
  const visible = schema.filter((c) => (c.visibleWhen ? c.visibleWhen(value) : true));
  const groups: { section: string | undefined; controls: typeof schema }[] = [];
  for (const control of visible) {
    const last = groups[groups.length - 1];
    if (last && last.section === control.section) last.controls.push(control);
    else groups.push({ section: control.section, controls: [control] });
  }

  const sectionNames = new Set(groups.map((g) => g.section).filter(Boolean));
  const extrasFor = (section: string | undefined, position: 'before' | 'after') =>
    section
      ? (extras ?? [])
          .filter((e) => e.section === section && (e.position ?? 'after') === position)
          .map((e) => e.node)
      : [];
  const orphanExtras = (extras ?? []).filter((e) => !sectionNames.has(e.section));
  const insertedExtras = orphanExtras.filter(
    (e) => e.afterSection && sectionNames.has(e.afterSection),
  );
  const unplacedExtras = orphanExtras.filter((e) => !insertedExtras.includes(e));
  const leadingExtras = unplacedExtras.filter((e) => e.position === 'before');
  const trailingExtras = unplacedExtras.filter((e) => e.position !== 'before');

  return (
    <aside
      className={cn(
        'flex h-full shrink-0 flex-col border-l border-border bg-card',
        // Mobile: a right-edge overlay drawer that slides in/out.
        'absolute inset-y-0 right-0 z-40 w-[340px] max-w-[85vw] shadow-2xl transition-transform duration-200',
        open ? 'translate-x-0' : 'translate-x-full',
        // Desktop: a static column in the flex row; collapse by width.
        'md:relative md:z-auto md:max-w-none md:translate-x-0 md:shadow-none md:transition-[width] md:duration-200',
        open ? 'md:w-[340px]' : 'md:w-0 md:overflow-hidden md:border-l-0',
      )}
    >
      {(title || onClose) && (
        <div className="flex h-10 shrink-0 items-center justify-between border-b border-border px-4">
          <span className="heading">{title}</span>
          {onClose && (
            <button
              type="button"
              onClick={onClose}
              aria-label="Hide settings"
              className="-mr-1 rounded-md p-1 text-muted-foreground/60 outline-none transition-colors hover:text-foreground focus-visible:ring-1 focus-visible:ring-ring md:hidden"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      )}
      {header && <div className="shrink-0 border-b border-border p-3">{header}</div>}
      <ScrollArea className="flex-1">
        <div className="flex flex-col gap-5 p-4">
          {leadingExtras.map((e, i) => (
            <Fragment key={`leading-extra-${e.section}-${i}`}>
              {i > 0 && <Separator />}
              <CollapsibleSection
                title={e.section}
                open={isOpen(e.section)}
                onToggle={() => toggleSection(e.section)}
              >
                {e.node}
              </CollapsibleSection>
            </Fragment>
          ))}
          {groups.map((group, gi) => {
            const controls = group.controls.map((control) => {
              const node = (
                <ControlRenderer
                  control={control}
                  value={value}
                  defaultValue={defaults[control.key]}
                  onChange={onChange}
                />
              );
              const k = String(control.key);
              return onTogglePencil ? (
                <PencilGutter
                  key={k}
                  checked={!!pencilKeys?.has(k)}
                  onToggle={() => onTogglePencil(k)}
                  align={control.kind === 'slider' ? 'center' : 'top'}
                >
                  {node}
                </PencilGutter>
              ) : (
                <Fragment key={k}>{node}</Fragment>
              );
            });
            const insertedAfter = insertedExtras.filter(
              (e) => e.afterSection === group.section,
            );
            return (
              <Fragment key={gi}>
                {(gi > 0 || leadingExtras.length > 0) && <Separator />}
                {group.section ? (
                  <CollapsibleSection
                    title={group.section}
                    open={isOpen(group.section)}
                    onToggle={() => toggleSection(group.section!)}
                  >
                    {extrasFor(group.section, 'before')}
                    {controls}
                    {extrasFor(group.section, 'after')}
                  </CollapsibleSection>
                ) : (
                  <div className="flex flex-col gap-3">{controls}</div>
                )}
                {insertedAfter.map((e, i) => (
                  <Fragment key={`inserted-extra-${e.section}-${i}`}>
                    <Separator />
                    <CollapsibleSection
                      title={e.section}
                      open={isOpen(e.section)}
                      onToggle={() => toggleSection(e.section)}
                    >
                      {e.node}
                    </CollapsibleSection>
                  </Fragment>
                ))}
              </Fragment>
            );
          })}
          {trailingExtras.map((e, i) => (
            <Fragment key={`extra-${e.section}-${i}`}>
              <Separator />
              <CollapsibleSection
                title={e.section}
                open={isOpen(e.section)}
                onToggle={() => toggleSection(e.section)}
              >
                {e.node}
              </CollapsibleSection>
            </Fragment>
          ))}
        </div>
      </ScrollArea>
    </aside>
  );
}
