// Generic undo/redo history: a past/future stack of state snapshots `T`.
//
// PURE — holds no app types and performs no cloning or I/O. The store
// (`use-sessions.ts`) supplies deep-cloned snapshots and applies the snapshot
// `undo`/`redo` hand back. Kept pure so the stack logic is unit-tested
// (`history.test.ts`) the same way the timeline engine is.

export interface History<T> {
  /** Pre-edit snapshots, oldest → newest. `undo` pops the last. */
  past: T[];
  /** Undone snapshots awaiting `redo`, next-to-redo first. */
  future: T[];
  /**
   * Coalescing bookkeeping: consecutive edits that share a `token` within
   * `COALESCE_MS` collapse into ONE undo step (so a slider drag is a single
   * entry, not dozens). `null` token never coalesces.
   */
  lastToken: string | null;
  lastTs: number;
}

/** Edits sharing a token closer together than this (ms) collapse into one step. */
export const COALESCE_MS = 500;
/** Cap the past stack so a long session can't grow memory without bound. */
export const MAX_HISTORY = 100;

export function emptyHistory<T>(): History<T> {
  return { past: [], future: [], lastToken: null, lastTs: 0 };
}

export const canUndo = (h: History<unknown> | undefined): boolean => !!h && h.past.length > 0;
export const canRedo = (h: History<unknown> | undefined): boolean => !!h && h.future.length > 0;

/**
 * Record the PRE-edit `snapshot`. A new edit clears the redo branch. When the
 * edit continues the previous gesture (same `token` within the time window),
 * the earlier pre-gesture snapshot is kept and nothing is pushed.
 */
export function record<T>(
  h: History<T>,
  snapshot: T,
  token: string | null,
  now: number,
): History<T> {
  if (
    token !== null &&
    token === h.lastToken &&
    now - h.lastTs < COALESCE_MS &&
    h.past.length > 0
  ) {
    // Continuation of the same gesture — the pre-gesture snapshot already sits
    // on the stack. Just extend the window (redo stays cleared by the first push).
    return { ...h, future: [], lastTs: now };
  }
  const past = [...h.past, snapshot];
  if (past.length > MAX_HISTORY) past.shift();
  return { past, future: [], lastToken: token, lastTs: now };
}

/**
 * Step back. `present` is the current live state (pushed onto the redo branch).
 * Returns the snapshot to restore + the updated history, or `null` if empty.
 */
export function undo<T>(h: History<T>, present: T): { history: History<T>; restore: T } | null {
  if (h.past.length === 0) return null;
  const restore = h.past[h.past.length - 1];
  return {
    history: {
      past: h.past.slice(0, -1),
      future: [present, ...h.future],
      lastToken: null,
      lastTs: 0,
    },
    restore,
  };
}

/** Step forward. Mirror of `undo`. */
export function redo<T>(h: History<T>, present: T): { history: History<T>; restore: T } | null {
  if (h.future.length === 0) return null;
  const [restore, ...rest] = h.future;
  return {
    history: {
      past: [...h.past, present],
      future: rest,
      lastToken: null,
      lastTs: 0,
    },
    restore,
  };
}
