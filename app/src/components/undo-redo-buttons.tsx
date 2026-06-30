import { Redo2, Undo2 } from 'lucide-react';
import { Button } from '@/components/ui/button';

/** Top-bar undo/redo, styled like flip. Pure presentational — driven by props. */
export function UndoRedoButtons({
  canUndo,
  canRedo,
  onUndo,
  onRedo,
}: {
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
}) {
  return (
    <div className="flex items-center gap-0.5">
      <Button
        variant="ghost"
        size="icon"
        onClick={onUndo}
        disabled={!canUndo}
        aria-label="Undo"
        title="Undo (⌘Z)"
      >
        <Undo2 />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        onClick={onRedo}
        disabled={!canRedo}
        aria-label="Redo"
        title="Redo (⌘⇧Z)"
      >
        <Redo2 />
      </Button>
    </div>
  );
}
