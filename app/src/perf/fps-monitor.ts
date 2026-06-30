/**
 * Singleton FPS / perf monitor — a diagnostic tool, NOT part of any experiment.
 *
 * Measures the *experienced* frame rate: a single requestAnimationFrame loop
 * timing `performance.now()` deltas. When the main thread is janky (heavy React
 * re-renders + WebGL), those deltas stretch and the reported FPS drops — so this
 * captures total page jank without living inside the R3F Canvas.
 *
 * Deliberately holds NO React state and never calls setState in its loop:
 * doing so would re-render React every frame, which is the very cost we're here
 * to diagnose. The panel reads the ring buffer imperatively (canvas draw).
 *
 * The loop only runs while `running` (panel visible OR logging on), so when the
 * tool is off it costs nothing. `perfMark()` is a single boolean check when
 * logging is off, so the instrumentation calls sprinkled around the app are
 * free to leave in permanently.
 */

const BUFFER_SIZE = 180; // ~3s at 60fps — the sparkline window
const STAT_WINDOW = 30; // frames averaged for the (flicker-free) numeric readout
const SUMMARY_MS = 1000; // 1-Hz console summary cadence while logging

/** Ring buffer of recent frame intervals in ms (oldest → newest order on read). */
const frameMs: number[] = [];
let writeIdx = 0;
let filled = false;

let panelVisible = false;
let logging = false;
/** External demand (e.g. the agent's get_perf sampling window). */
let retained = 0;
let running = false;

let rafId: number | null = null;
let lastTs = 0;

// Subscribers notified once per measured frame (the panel uses this to redraw).
const frameSubs = new Set<() => void>();

// 1-Hz summary accumulator.
let windowStart = 0;
let windowCount = 0;
let windowMin = Infinity;
let windowMax = 0;
let windowSum = 0;

function pushFrame(ms: number) {
  frameMs[writeIdx] = ms;
  writeIdx = (writeIdx + 1) % BUFFER_SIZE;
  if (writeIdx === 0) filled = true;
}

/** Frame intervals (ms), oldest first. */
export function getFrames(): number[] {
  if (!filled) return frameMs.slice(0, writeIdx);
  return frameMs.slice(writeIdx).concat(frameMs.slice(0, writeIdx));
}

export interface FpsStats {
  fps: number; // smoothed current
  avg: number;
  min: number;
  max: number;
}

export function getStats(): FpsStats {
  const frames = getFrames();
  if (frames.length === 0) return { fps: 0, avg: 0, min: 0, max: 0 };
  const recent = frames.slice(-STAT_WINDOW);
  const meanMs = recent.reduce((a, b) => a + b, 0) / recent.length;
  let min = Infinity;
  let max = 0;
  for (const ms of frames) {
    const f = ms > 0 ? 1000 / ms : 0;
    if (f < min) min = f;
    if (f > max) max = f;
  }
  return {
    fps: meanMs > 0 ? 1000 / meanMs : 0,
    avg: frames.length ? 1000 / (frames.reduce((a, b) => a + b, 0) / frames.length) : 0,
    min: min === Infinity ? 0 : min,
    max,
  };
}

/** Instantaneous FPS from the most recent frame (used to tag marks). */
function currentFps(): number {
  const frames = getFrames();
  const last = frames[frames.length - 1];
  return last && last > 0 ? 1000 / last : 0;
}

function tick(now: number) {
  if (lastTs !== 0) {
    const dt = now - lastTs;
    pushFrame(dt);

    if (logging) {
      const fps = dt > 0 ? 1000 / dt : 0;
      windowCount += 1;
      windowSum += fps;
      if (fps < windowMin) windowMin = fps;
      if (fps > windowMax) windowMax = fps;
      if (now - windowStart >= SUMMARY_MS) {
        const avg = windowCount ? windowSum / windowCount : 0;
        // eslint-disable-next-line no-console
        console.log(
          `[perf] 1s avg ${avg.toFixed(1)} min ${windowMin.toFixed(1)} max ${windowMax.toFixed(1)} frames ${windowCount}`,
        );
        windowStart = now;
        windowCount = 0;
        windowSum = 0;
        windowMin = Infinity;
        windowMax = 0;
      }
    }

    for (const cb of frameSubs) cb();
  }
  lastTs = now;
  rafId = requestAnimationFrame(tick);
}

function start() {
  if (rafId !== null) return;
  lastTs = 0;
  windowStart = performance.now();
  windowCount = 0;
  windowSum = 0;
  windowMin = Infinity;
  windowMax = 0;
  rafId = requestAnimationFrame(tick);
}

function stop() {
  if (rafId !== null) {
    cancelAnimationFrame(rafId);
    rafId = null;
  }
}

function syncRunning() {
  const next = panelVisible || logging || retained > 0;
  if (next === running) return;
  running = next;
  if (running) start();
  else stop();
}

export function setEnabled(visible: boolean) {
  panelVisible = visible;
  syncRunning();
}

export function setLogging(on: boolean) {
  logging = on;
  syncRunning();
}

export function isLogging(): boolean {
  return logging;
}

/**
 * Keep the monitor loop running while a caller needs samples (the agent's
 * `get_perf`), independent of the panel/logging toggles. Returns a release;
 * releasing twice is a no-op.
 */
export function retainMonitor(): () => void {
  retained += 1;
  syncRunning();
  let released = false;
  return () => {
    if (released) return;
    released = true;
    retained -= 1;
    syncRunning();
  };
}

/** Register a per-frame callback (the panel's canvas draw). Returns unsubscribe. */
export function subscribeFrame(cb: () => void): () => void {
  frameSubs.add(cb);
  return () => frameSubs.delete(cb);
}

/**
 * Annotate the log with a UI/experiment action, tagged with the current FPS, so
 * we can correlate which action tanks the rate. No-op (one boolean check) when
 * logging is off.
 */
export function perfMark(label: string, detail?: unknown) {
  if (!logging) return;
  const fps = currentFps();
  // eslint-disable-next-line no-console
  console.log(
    `[perf] ${label}${detail !== undefined ? ' ' + safeJson(detail) : ''} | fps=${fps.toFixed(1)} @ ${performance.now().toFixed(0)}ms`,
  );
}

function safeJson(v: unknown): string {
  try {
    return typeof v === 'string' ? v : JSON.stringify(v);
  } catch {
    return String(v);
  }
}
