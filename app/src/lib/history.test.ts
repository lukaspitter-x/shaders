import { describe, expect, it } from 'vitest';
import {
  COALESCE_MS,
  MAX_HISTORY,
  canRedo,
  canUndo,
  emptyHistory,
  record,
  redo,
  undo,
} from './history';

// Snapshots are opaque to the stack; use plain strings as stand-in states.
const h0 = emptyHistory<string>();

describe('record', () => {
  it('pushes the pre-edit snapshot and clears the redo branch', () => {
    const h = record(h0, 'A', 'set:x', 0);
    expect(h.past).toEqual(['A']);
    expect(h.future).toEqual([]);
    expect(canUndo(h)).toBe(true);
    expect(canRedo(h)).toBe(false);
  });

  it('coalesces same-token edits within the time window into one entry', () => {
    let h = record(h0, 'A', 'set:x', 0);
    h = record(h, 'B', 'set:x', 100);
    h = record(h, 'C', 'set:x', 200);
    expect(h.past).toEqual(['A']); // only the pre-gesture snapshot kept
  });

  it('starts a new entry when the token differs', () => {
    let h = record(h0, 'A', 'set:x', 0);
    h = record(h, 'B', 'set:y', 50);
    expect(h.past).toEqual(['A', 'B']);
  });

  it('starts a new entry once the window has elapsed', () => {
    let h = record(h0, 'A', 'set:x', 0);
    h = record(h, 'B', 'set:x', COALESCE_MS + 1);
    expect(h.past).toEqual(['A', 'B']);
  });

  it('never coalesces a null token', () => {
    let h = record(h0, 'A', null, 0);
    h = record(h, 'B', null, 10);
    expect(h.past).toEqual(['A', 'B']);
  });

  it('caps the past stack at MAX_HISTORY, dropping the oldest', () => {
    let h = h0;
    for (let i = 0; i < MAX_HISTORY + 5; i++) h = record(h, `s${i}`, `t${i}`, i);
    expect(h.past.length).toBe(MAX_HISTORY);
    expect(h.past[0]).toBe('s5'); // s0..s4 dropped
  });
});

describe('undo / redo', () => {
  it('returns null when there is nothing to undo or redo', () => {
    expect(undo(h0, 'live')).toBeNull();
    expect(redo(h0, 'live')).toBeNull();
  });

  it('restores the last snapshot and parks the present on the redo branch', () => {
    const h = record(h0, 'A', 'set:x', 0); // present is now post-edit, say 'B'
    const u = undo(h, 'B')!;
    expect(u.restore).toBe('A');
    expect(u.history.past).toEqual([]);
    expect(u.history.future).toEqual(['B']);
    expect(canRedo(u.history)).toBe(true);
  });

  it('round-trips through undo then redo back to the live state', () => {
    const h = record(h0, 'A', 'set:x', 0);
    const u = undo(h, 'B')!; // restore 'A', future ['B']
    const r = redo(u.history, 'A')!; // present is 'A' after the undo applied
    expect(r.restore).toBe('B');
    expect(r.history.past).toEqual(['A']);
    expect(r.history.future).toEqual([]);
  });

  it('a fresh edit after undo clears the redo branch', () => {
    const h = record(h0, 'A', 'set:x', 0);
    const u = undo(h, 'B')!; // future ['B']
    const after = record(u.history, 'A', 'set:y', 1000);
    expect(after.future).toEqual([]);
    expect(after.past).toEqual(['A']);
  });

  it('walks a multi-step stack back and forward in order', () => {
    let h = h0;
    h = record(h, 'S0', 'a', 0); // edit → S1
    h = record(h, 'S1', 'b', 1000); // edit → S2
    h = record(h, 'S2', 'c', 2000); // edit → S3 (live)
    const u1 = undo(h, 'S3')!;
    expect(u1.restore).toBe('S2');
    const u2 = undo(u1.history, 'S2')!;
    expect(u2.restore).toBe('S1');
    const u3 = undo(u2.history, 'S1')!;
    expect(u3.restore).toBe('S0');
    expect(undo(u3.history, 'S0')).toBeNull();
  });
});
