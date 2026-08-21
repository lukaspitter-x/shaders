/**
 * Parse Pencil's annotated GLSL into a settings schema + uniform manifest.
 *
 * Pencil drives its control panel from JSDoc-style annotations on `uniform`
 * declarations. The annotated `.glsl` file is therefore BOTH the shader and the
 * schema — we parse it here so the workbench panel matches Pencil's exactly.
 *
 *   /** @resolution *\/            → system uniform: canvas size (vec2)
 *   /** @time *\/                  → system uniform: elapsed seconds (float)
 *   /** @sdf *\/                   → system uniform: host shape SDF (sampler2D)
 *   /** @label .. @default .. @range a, b *\/  float  → slider control
 *   /** @label .. @color @default #rrggbb *\/  vec3   → color control
 *
 * Pure module (no DOM / WebGL) so it can be unit-tested in isolation.
 */
import type { SettingsSchema } from '@/settings/schema';
import { normalizeHex } from '@/lib/hex';

export type UniformRole = 'resolution' | 'time' | 'mouse' | 'sdf' | 'user';

export interface ParsedUniform {
  name: string;
  glslType: string;
  role: UniformRole;
  control?: 'slider' | 'number' | 'color' | 'image' | 'select' | 'bezier' | 'switch';
  label?: string;
  hint?: string;
  default?: number | string | number[];
  min?: number;
  max?: number;
}

/** Setting values are keyed by uniform name: number for floats, hex for colors, tuple for bezier. */
export type ShaderValues = Record<string, number | string | number[] | boolean>;

export interface ParsedShader {
  uniforms: ParsedUniform[];
  schema: SettingsSchema<ShaderValues>;
  defaults: ShaderValues;
  /** role → uniform name, so the renderer knows which uniform to feed. */
  system: { resolution?: string; time?: string; mouse?: string; sdf?: string };
  /** User image sampler uniform names (sampler2D with @label, not @sdf). */
  images: string[];
  /** Envelope curve sampler uniform names (sampler2D with @envelope). */
  envelopes: string[];
}

/**
 * Matches a `/** ... *\/` doc block immediately preceding a `uniform T name;`,
 * with an optional `// SECTION: Name` line comment above it. Section grouping
 * lives in a line comment — NOT an `@section` doc tag — because Pencil hard-
 * rejects any `@directive` it doesn't recognize, while it ignores line comments
 * entirely (see docs/pencil-compat.md). Groups: 1=section, 2=body, 3=type, 4=name.
 */
const UNIFORM_RE =
  /(?:\/\/\s*SECTION:\s*([^\r\n]+?)\s*\r?\n\s*)?\/\*\*([\s\S]*?)\*\/\s*uniform\s+(\w+)\s+(\w+)\s*;/g;

/** Strip the per-line `*` gutter from a doc-comment body. */
function cleanBody(body: string): string {
  return body
    .split('\n')
    .map((l) => l.replace(/^\s*\*?\s?/, '').replace(/\s+$/, ''))
    .join('\n')
    .trim();
}

interface Tags {
  description: string;
  flags: Set<string>;
  values: Record<string, string>;
}

/** Split a doc body into leading prose + `@tag value` pairs (`@flag` → flag). */
function parseTags(body: string): Tags {
  const text = cleanBody(body);
  const firstAt = text.search(/@\w/);
  const description = (firstAt === -1 ? text : text.slice(0, firstAt)).trim();
  const flags = new Set<string>();
  const values: Record<string, string> = {};
  const re = /@(\w+)([^@]*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const tag = m[1];
    const val = m[2].trim();
    if (val) values[tag] = val;
    else flags.add(tag);
  }
  return { description, flags, values };
}

/** A "nice" slider step (~200 divisions snapped to a 1/2/5 decade). */
function niceStep(min: number, max: number): number {
  const span = Math.abs(max - min);
  if (!span || !Number.isFinite(span)) return 0.01;
  const raw = span / 200;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const norm = raw / mag;
  const nice = norm < 1.5 ? 1 : norm < 3.5 ? 2 : norm < 7.5 ? 5 : 10;
  return nice * mag;
}

/**
 * Sanitize values against the schema on read (non-destructive). Clamps numeric
 * controls to their range so an out-of-range stored/stale value can never reach
 * the shader. Colors pass through — the renderer's hex→rgb already tolerates bad
 * input, and clamping a half-typed hex would fight the color field. Per the kit:
 * the schema doubles as the validator, applied read-side.
 */
export function sanitizeValues(
  schema: SettingsSchema<ShaderValues>,
  values: ShaderValues,
): ShaderValues {
  const out: ShaderValues = { ...values };
  for (const c of schema) {
    // Selects store option-value STRINGS; a stale value from before a control
    // changed kind (e.g. slider → select) arrives numeric. Coerce by rounding
    // and clamping into the option list so the dropdown never shows blank.
    if (c.kind === 'select') {
      const v = out[c.key];
      if (v === undefined || c.options.length === 0) continue;
      if (typeof v === 'string' && c.options.some((o) => o.value === v)) continue;
      const n = Math.round(Number(v));
      const idx = Math.min(c.options.length - 1, Math.max(0, Number.isFinite(n) ? n : 0));
      out[c.key] = c.options[idx].value;
      continue;
    }
    if (c.kind !== 'slider' && c.kind !== 'number') continue;
    const n = typeof out[c.key] === 'number' ? (out[c.key] as number) : Number(out[c.key]);
    if (!Number.isFinite(n)) continue;
    let clamped = n;
    if (c.kind === 'slider') clamped = Math.min(c.max, Math.max(c.min, n));
    else {
      if (c.min !== undefined) clamped = Math.max(c.min, clamped);
      if (c.max !== undefined) clamped = Math.min(c.max, clamped);
    }
    out[c.key] = clamped;
  }
  return out;
}

export function parseShader(source: string): ParsedShader {
  const uniforms: ParsedUniform[] = [];
  const schema: SettingsSchema<ShaderValues> = [];
  const defaults: ShaderValues = {};
  const system: ParsedShader['system'] = {};
  const images: string[] = [];
  const envelopes: string[] = [];

  UNIFORM_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = UNIFORM_RE.exec(source))) {
    const [, sectionMarker, body, glslType, name] = m;
    const { description, flags, values } = parseTags(body);

    let role: UniformRole = 'user';
    if (flags.has('resolution')) role = 'resolution';
    else if (flags.has('time')) role = 'time';
    else if (flags.has('mouse')) role = 'mouse';
    else if (flags.has('sdf')) role = 'sdf';

    if (role !== 'user') {
      system[role] = name;
      uniforms.push({ name, glslType, role });
      continue;
    }

    const label = values.label ?? name;
    const hint = description || undefined;
    const section = sectionMarker?.trim() || values.section;
    const u: ParsedUniform = { name, glslType, role, label, hint };

    const isColor = flags.has('color') || (glslType === 'vec3' && !!values.default?.startsWith('#'));
    if (isColor) {
      u.control = 'color';
      u.default = normalizeHex(values.default ?? '') ?? '#000000';
      schema.push({ key: name, label, hint, kind: 'color' });
    } else if (glslType === 'vec4' && flags.has('bezier')) {
      u.control = 'bezier';
      const parts = (values.default ?? '0.25, 0.1, 0.25, 1.0').split(',').map((s) => Number(s.trim()));
      u.default = parts.length === 4 ? parts : [0.25, 0.1, 0.25, 1.0];
      schema.push({ key: name, label, hint, kind: 'bezier' });
    } else if (glslType === 'float' && flags.has('switch')) {
      u.control = 'switch';
      defaults[name] = values.default === '1' || values.default === 'true';
      schema.push({ key: name, label, hint, kind: 'switch' });
    } else if (glslType === 'float' && values.select) {
      u.control = 'select';
      const options = values.select.split(',').map((s, i) => ({ value: String(i), label: s.trim() }));
      u.default = values.default !== undefined ? String(Number(values.default)) : '0';
      schema.push({ key: name, label, hint, kind: 'select', options });
    } else if (glslType === 'float') {
      u.default = values.default !== undefined ? Number(values.default) : 0;
      if (values.range) {
        const [min, max] = values.range.split(',').map((s) => Number(s.trim()));
        u.control = 'slider';
        u.min = min;
        u.max = max;
        const step = values.step !== undefined ? Number(values.step) : niceStep(min, max);
        schema.push({ key: name, label, hint, kind: 'slider', min, max, step });
      } else {
        u.control = 'number';
        schema.push({ key: name, label, hint, kind: 'number' });
      }
    } else if (glslType === 'sampler2D' && flags.has('envelope')) {
      u.control = 'envelope' as typeof u.control;
      const pts = values.default
        ? values.default.split(',').map((s) => Number(s.trim()))
        : [0, 0, 1, 1];
      defaults[name] = pts;
      schema.push({ key: name, label, hint, kind: 'envelope' });
      envelopes.push(name);
    } else if (glslType === 'sampler2D') {
      u.control = 'image';
      u.default = '';
      schema.push({ key: name, label, hint, kind: 'image', assets: values.assets });
      images.push(name);
    }
    // (Unsupported user types fall through with no control — added as needed.)

    if (section && schema.length > 0) {
      const last = schema[schema.length - 1];
      if (last.key === name) last.section = section;
    }

    if (u.default !== undefined) defaults[name] = u.default;
    uniforms.push(u);
  }

  return { uniforms, schema, defaults, system, images, envelopes };
}
