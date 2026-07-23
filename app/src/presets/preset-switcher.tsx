import { useState } from 'react';
import { Check, Copy, MoreHorizontal, Pencil, Plus, RotateCcw, Save, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { cn } from '@/lib/cn';
import type { UsePresets } from './use-presets';

export function PresetSwitcher({ store }: { store: UsePresets }) {
  const {
    presets,
    active,
    createPreset,
    duplicatePreset,
    deletePreset,
    renamePreset,
    switchPreset,
    dirty,
    commitPresets,
    revertToPresets,
  } = store;
  const [renameOpen, setRenameOpen] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [revertOpen, setRevertOpen] = useState(false);

  const openRename = () => {
    setDraftName(active?.name ?? '');
    setRenameOpen(true);
  };
  const commitRename = () => {
    if (active && draftName.trim()) renamePreset(active.id, draftName.trim());
    setRenameOpen(false);
  };

  return (
    <TooltipProvider delayDuration={200}>
    <div className="flex items-center gap-1.5">
      <Select value={active?.id ?? ''} onValueChange={switchPreset}>
        <SelectTrigger className="flex-1">
          <SelectValue placeholder="Preset" />
        </SelectTrigger>
        <SelectContent>
          {presets.map((p) => (
            <SelectItem key={p.id} value={p.id}>
              {p.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      <Tooltip>
        <TooltipTrigger asChild>
          <Button
            size="sm"
            variant={dirty ? 'default' : 'ghost'}
            onClick={() => dirty && commitPresets()}
            aria-disabled={!dirty}
            className={cn(!dirty && 'cursor-default text-muted-foreground')}
          >
            {dirty ? <Save /> : <Check />}
            {dirty ? 'Save' : 'Saved'}
          </Button>
        </TooltipTrigger>
        <TooltipContent side="bottom">
          {dirty
            ? 'Save presets — writes your changes to sessions.json, the file tracked in git. Until you click this, edits live only in a local working copy.'
            : 'All changes saved. Edits auto-save to a local working copy; this button commits them to the git-tracked sessions.json.'}
        </TooltipContent>
      </Tooltip>

      <Button size="icon" variant="outline" onClick={() => createPreset()} title="New preset">
        <Plus />
      </Button>

      {/* modal={false}: this menu opens modal Dialogs (Rename/Revert). With a
          modal menu, both layers toggle `pointer-events: none` on <body> and a
          teardown race can leave it stuck — the whole app then ignores clicks
          ("freezes"). Non-modal, only the Dialog manages the body lock. */}
      <DropdownMenu modal={false}>
        <DropdownMenuTrigger asChild>
          <Button size="icon" variant="outline" title="Preset actions">
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => duplicatePreset()}>
            <Copy /> Duplicate
          </DropdownMenuItem>
          <DropdownMenuItem onClick={openRename}>
            <Pencil /> Rename
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onClick={() => setRevertOpen(true)} disabled={!dirty}>
            <RotateCcw /> Revert to saved presets
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => active && deletePreset(active.id)}
            className="text-destructive focus:text-destructive"
            disabled={presets.length <= 1}
          >
            <Trash2 /> Delete
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rename preset</DialogTitle>
          </DialogHeader>
          <Input
            value={draftName}
            autoFocus
            onChange={(e) => setDraftName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && commitRename()}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setRenameOpen(false)}>
              Cancel
            </Button>
            <Button onClick={commitRename}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={revertOpen} onOpenChange={setRevertOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Revert to saved presets?</DialogTitle>
            <DialogDescription>
              Discards all unsaved working changes (across every shader) and restores the last
              saved presets. This can't be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRevertOpen(false)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() => {
                revertToPresets();
                setRevertOpen(false);
              }}
            >
              Revert
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
    </TooltipProvider>
  );
}
