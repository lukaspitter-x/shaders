import type { ShaderValues } from './parse-annotations';

/**
 * Prepare a shader for Pencil export by inlining hidden uniforms as constants.
 *
 * - System uniforms (`@resolution`, `@time`, `@mouse`, `@sdf`) are always kept.
 * - User uniforms in `visibleKeys` keep their full doc block + uniform declaration.
 * - Hidden user uniforms are replaced with a `#define` using their CURRENT value
 *   from the workbench (falling back to `@default` / GLSL zero), removing the
 *   uniform entirely so Pencil won't generate a control for them.
 */
export function stripHiddenAnnotations(
  source: string,
  visibleKeys: Set<string>,
  currentValues: ShaderValues,
): string {
  const SYSTEM_RE = /@(resolution|time|mouse|sdf)\b/;

  // Match: optional `// SECTION:` line + `/** ... */` doc block + `uniform T name;`
  const RE =
    /(\/\/\s*SECTION:\s*[^\r\n]+?\s*\r?\n\s*)?(\/\*\*[\s\S]*?\*\/\s*)(uniform\s+(\w+)\s+(\w+)\s*;)/g;

  return source.replace(RE, (full, _sectionLine, docBlock, _uniformDecl, glslType, uniformName) => {
    if (SYSTEM_RE.test(docBlock)) return full;
    if (visibleKeys.has(uniformName)) return full;

    const glslValue = toGlsl(currentValues[uniformName], glslType, docBlock);
    return `#define ${uniformName} ${glslValue}`;
  });
}

function toGlsl(
  value: ShaderValues[string] | undefined,
  glslType: string,
  docBlock: string,
): string {
  if (value !== undefined) {
    if (glslType === 'vec3' && typeof value === 'string' && value.startsWith('#')) {
      return hexToVec3(value);
    }
    if (glslType === 'float' && typeof value === 'number') {
      return formatFloat(value);
    }
    if (glslType === 'int' && typeof value === 'number') {
      return String(Math.round(value));
    }
    if (glslType === 'vec4' && Array.isArray(value) && value.length === 4) {
      return `vec4(${value.map((v) => formatFloat(v)).join(', ')})`;
    }
  }

  // Fall back to @default from the doc block.
  return extractDefault(docBlock, glslType);
}

function hexToVec3(hex: string): string {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16) / 255;
  const g = parseInt(h.slice(2, 4), 16) / 255;
  const b = parseInt(h.slice(4, 6), 16) / 255;
  return `vec3(${r.toFixed(4)}, ${g.toFixed(4)}, ${b.toFixed(4)})`;
}

function extractDefault(docBlock: string, glslType: string): string {
  const m = docBlock.match(/@default\s+([^@*\n]+)/);
  const raw = m?.[1]?.trim();

  if (glslType === 'vec3') {
    if (raw?.startsWith('#')) return hexToVec3(raw);
    return raw ?? 'vec3(0.0)';
  }
  if (glslType === 'vec2') return raw ?? 'vec2(0.0)';
  if (glslType === 'vec4') {
    if (raw) {
      const parts = raw.split(',').map((s) => s.trim());
      if (parts.length === 4) return `vec4(${parts.join(', ')})`;
    }
    return 'vec4(0.0)';
  }
  if (glslType === 'float') return formatFloat(raw != null ? Number(raw) : 0);
  if (glslType === 'int') return raw ?? '0';

  return raw ?? '0.0';
}

function formatFloat(n: number): string {
  if (!Number.isFinite(n)) return '0.0';
  const str = String(n);
  return str.includes('.') ? str : str + '.0';
}
