import { useCallback, useRef } from 'react';
import { Field } from './field';

export type Envelope = number[];

const PAD = 18;
const W = 176;
const H = 176;
const SVG_W = W + PAD * 2;
const SVG_H = H + PAD * 2;

const POINT_R = 6;
const HIT_R = 13;

function toPx(x: number, y: number) {
  return { x: PAD + x * W, y: PAD + (1 - y) * H };
}

function fromPx(px: number, py: number): [number, number] {
  return [
    Math.max(0, Math.min(1, (px - PAD) / W)),
    Math.max(0, Math.min(1, 1 - (py - PAD) / H)),
  ];
}

function getPoints(value: Envelope): [number, number][] {
  const pts: [number, number][] = [];
  for (let i = 0; i < value.length - 1; i += 2) {
    pts.push([value[i], value[i + 1]]);
  }
  pts.sort((a, b) => a[0] - b[0]);
  return pts;
}

function flatten(pts: [number, number][]): Envelope {
  const out: number[] = [];
  for (const [x, y] of pts) {
    out.push(Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000);
  }
  return out;
}

export function EnvelopeControl({
  label,
  hint,
  value,
  onChange,
  onReset,
}: {
  label: string;
  hint?: string;
  value: Envelope;
  onChange: (v: Envelope) => void;
  onReset?: () => void;
}) {
  const svgRef = useRef<SVGSVGElement | null>(null);
  const dragRef = useRef<number | null>(null);
  const suppressClickRef = useRef(false);
  const pts = getPoints(value);

  const getSvgCoords = useCallback(
    (e: PointerEvent | React.PointerEvent): [number, number] => {
      const svg = svgRef.current;
      if (!svg) return [0, 0];
      const r = svg.getBoundingClientRect();
      const sx = r.width / SVG_W;
      const sy = r.height / SVG_H;
      const px = (e.clientX - r.left) / sx;
      const py = (e.clientY - r.top) / sy;
      return fromPx(px, py);
    },
    [],
  );

  const onMove = useCallback(
    (e: PointerEvent) => {
      const idx = dragRef.current;
      if (idx === null) return;
      const [x, y] = getSvgCoords(e);
      const next = [...pts] as [number, number][];
      if (idx === 0) {
        next[0] = [0, y];
      } else if (idx === pts.length - 1) {
        next[idx] = [1, y];
      } else {
        const minX = next[idx - 1][0] + 0.01;
        const maxX = next[idx + 1][0] - 0.01;
        next[idx] = [Math.max(minX, Math.min(maxX, x)), y];
      }
      onChange(flatten(next));
    },
    [pts, onChange, getSvgCoords],
  );

  const startDrag = (idx: number) => (e: React.PointerEvent) => {
    e.preventDefault();
    e.stopPropagation();
    dragRef.current = idx;
    suppressClickRef.current = true;
    const move = (ev: PointerEvent) => onMove(ev);
    const up = () => {
      dragRef.current = null;
      setTimeout(() => { suppressClickRef.current = false; }, 50);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  };

  const handleClick = useCallback(
    (e: React.PointerEvent) => {
      if (dragRef.current !== null) return;
      if (suppressClickRef.current) return;
      const svg = svgRef.current;
      if (!svg) return;
      const r = svg.getBoundingClientRect();
      const sx = r.width / SVG_W;
      const sy = r.height / SVG_H;
      const px = (e.clientX - r.left) / sx;
      const py = (e.clientY - r.top) / sy;

      for (const pt of pts) {
        const pp = toPx(pt[0], pt[1]);
        const dx = px - pp.x;
        const dy = py - pp.y;
        if (dx * dx + dy * dy < HIT_R * HIT_R) return;
      }

      const [x, y] = fromPx(px, py);
      if (x <= 0.01 || x >= 0.99) return;
      const next = [...pts, [x, y] as [number, number]];
      next.sort((a, b) => a[0] - b[0]);
      onChange(flatten(next));
    },
    [pts, onChange],
  );

  const handleDoubleClick = (idx: number) => (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (idx === 0 || idx === pts.length - 1) return;
    suppressClickRef.current = true;
    const next = pts.filter((_, i) => i !== idx);
    onChange(flatten(next));
    setTimeout(() => { suppressClickRef.current = false; }, 100);
  };

  const polyline = pts.map((p) => {
    const pp = toPx(p[0], p[1]);
    return `${pp.x},${pp.y}`;
  }).join(' ');

  const box0 = toPx(0, 1);
  const box1 = toPx(1, 0);

  return (
    <Field label={label} hint={hint} onReset={onReset}>
      <svg
        ref={svgRef}
        width="100%"
        viewBox={`0 0 ${SVG_W} ${SVG_H}`}
        className="touch-none rounded-md border border-border bg-secondary/30"
        onPointerUp={handleClick}
      >
        <rect
          x={box0.x} y={box0.y}
          width={box1.x - box0.x} height={box1.y - box0.y}
          fill="none" stroke="hsl(var(--border))" strokeDasharray="2 3"
        />
        {/* diagonal guide */}
        <line
          x1={box0.x} y1={box1.y} x2={box1.x} y2={box0.y}
          stroke="hsl(var(--border))" strokeDasharray="2 3"
        />
        {/* polyline */}
        <polyline
          points={polyline}
          fill="none" stroke="hsl(var(--foreground))" strokeWidth={2}
        />
        {/* points */}
        {pts.map((p, i) => {
          const pp = toPx(p[0], p[1]);
          const isEnd = i === 0 || i === pts.length - 1;
          return (
            <g key={i}>
              <circle
                cx={pp.x} cy={pp.y} r={HIT_R}
                fill="transparent"
                className="cursor-grab active:cursor-grabbing"
                onPointerDown={startDrag(i)}
                onDoubleClick={handleDoubleClick(i)}
              />
              <circle
                cx={pp.x} cy={pp.y}
                r={isEnd ? 4 : POINT_R}
                fill={isEnd ? 'hsl(var(--muted-foreground))' : 'hsl(var(--primary))'}
                className="pointer-events-none"
              />
            </g>
          );
        })}
      </svg>
    </Field>
  );
}
