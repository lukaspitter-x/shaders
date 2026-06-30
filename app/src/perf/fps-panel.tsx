import { useEffect, useRef } from 'react';
import { Activity, ScrollText } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/cn';
import { getFrames, getStats, setEnabled, setLogging, subscribeFrame } from './fps-monitor';

const SPARK_W = 96;
const SPARK_H = 22;
const TARGET_FPS = 60; // full-height bar
const DROP_FPS = 30; // below this, the bar is tinted "bad"

/**
 * Top-bar FPS readout. Two independent ghost toggles (show the readout / turn
 * logging on) plus an inline canvas sparkline + numeric FPS. Draws imperatively
 * from the monitor's ring buffer (no per-frame React re-render — that's the cost
 * we're diagnosing). Controlled by `App`; mirrors the settings-toggle button.
 */
export function FpsPanel({
  visible,
  logging,
  onToggleVisible,
  onToggleLogging,
}: {
  visible: boolean;
  logging: boolean;
  onToggleVisible: () => void;
  onToggleLogging: () => void;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const numRef = useRef<HTMLSpanElement>(null);
  // Theme colors resolved from CSS vars (refreshed on theme change), so the
  // per-frame draw never forces a style recalc with getComputedStyle.
  const colors = useRef({ fg: '#888', muted: '#888', bad: '#e11' });

  // Keep the singleton's flags in sync with App-owned state.
  useEffect(() => setEnabled(visible), [visible]);
  useEffect(() => setLogging(logging), [logging]);

  // Resolve theme colors once + on theme (.dark class) changes.
  useEffect(() => {
    const read = () => {
      const cs = getComputedStyle(document.documentElement);
      const v = (name: string, fallback: string) => {
        const raw = cs.getPropertyValue(name).trim();
        return raw ? `hsl(${raw})` : fallback;
      };
      colors.current = {
        fg: v('--foreground', '#888'),
        muted: v('--muted-foreground', '#888'),
        bad: v('--destructive', '#e11'),
      };
    };
    read();
    const mo = new MutationObserver(read);
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    return () => mo.disconnect();
  }, []);

  // Draw loop — only while the readout is shown.
  useEffect(() => {
    if (!visible) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = SPARK_W * dpr;
    canvas.height = SPARK_H * dpr;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const draw = () => {
      const frames = getFrames();
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const n = frames.length;
      if (n > 0) {
        const bw = canvas.width / n;
        for (let i = 0; i < n; i++) {
          const fps = frames[i] > 0 ? 1000 / frames[i] : 0;
          const h = Math.min(1, fps / TARGET_FPS) * canvas.height;
          ctx.fillStyle = fps < DROP_FPS ? colors.current.bad : colors.current.fg;
          ctx.globalAlpha = fps < DROP_FPS ? 0.85 : 0.5;
          ctx.fillRect(i * bw, canvas.height - h, Math.max(1, bw - dpr * 0.5), h);
        }
        ctx.globalAlpha = 1;
      }
      if (numRef.current) {
        const { fps } = getStats();
        numRef.current.textContent = `${Math.round(fps)} fps`;
        numRef.current.style.color = fps < DROP_FPS ? colors.current.bad : colors.current.muted;
      }
    };

    draw();
    const unsub = subscribeFrame(draw);
    return unsub;
  }, [visible]);

  return (
    <div className="flex items-center gap-1.5">
      <Button
        variant="ghost"
        size="icon"
        onClick={onToggleVisible}
        aria-label={visible ? 'Hide FPS' : 'Show FPS'}
        aria-pressed={visible}
        title={visible ? 'Hide FPS readout' : 'Show FPS readout'}
        className={cn(visible && 'text-foreground')}
      >
        <Activity />
      </Button>

      {visible && (
        <div className="flex items-center gap-1.5" title="Frame rate over time">
          <canvas
            ref={canvasRef}
            style={{ width: SPARK_W, height: SPARK_H }}
            className="rounded-sm bg-secondary/60"
          />
          <span
            ref={numRef}
            className="w-12 shrink-0 text-right text-[11px] tabular-nums text-muted-foreground"
          >
            – fps
          </span>
        </div>
      )}

      <Button
        variant="ghost"
        size="icon"
        onClick={onToggleLogging}
        aria-label={logging ? 'Stop perf logging' : 'Start perf logging'}
        aria-pressed={logging}
        title={logging ? 'Perf logging ON — click to stop' : 'Log perf marks to console'}
        className={cn(logging && 'bg-primary text-primary-foreground hover:bg-primary/90')}
      >
        <ScrollText />
      </Button>
    </div>
  );
}
