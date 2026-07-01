/**
 * Prepare a shader for Pencil export by inlining hidden uniforms as constants.
 *
 * - System uniforms (`@resolution`, `@time`, `@mouse`, `@sdf`) are always kept.
 * - User uniforms in `visibleKeys` keep their full doc block + uniform declaration.
 * - Hidden user uniforms are replaced with a `#define` using their `@default`
 *   value (or the GLSL zero for that type), removing the uniform entirely so
 *   Pencil won't generate a control for them.
 */
export function stripHiddenAnnotations(source: string, visibleKeys: Set<string>): string {
  const SYSTEM_RE = /@(resolution|time|mouse|sdf)\b/;

  // Match: optional `// SECTION:` line + `/** ... */` doc block + `uniform T name;`
  const RE =
    /(\/\/\s*SECTION:\s*[^\r\n]+?\s*\r?\n\s*)?(\/\*\*[\s\S]*?\*\/\s*)(uniform\s+(\w+)\s+(\w+)\s*;)/g;

  return source.replace(RE, (full, _sectionLine, docBlock, _uniformDecl, glslType, uniformName) => {
    // System uniforms — always preserve.
    if (SYSTEM_RE.test(docBlock)) return full;

    // Visible user uniforms — keep everything.
    if (visibleKeys.has(uniformName)) return full;

    // Hidden user uniform — extract @default, replace with #define.
    const defaultValue = extractDefault(docBlock, glslType);
    return `#define ${uniformName} ${defaultValue}`;
  });
}

function extractDefault(docBlock: string, glslType: string): string {
  const m = docBlock.match(/@default\s+([^@*\n]+)/);
  const raw = m?.[1]?.trim();

  if (glslType === 'vec3') {
    if (raw?.startsWith('#')) {
      const hex = raw.replace('#', '');
      const r = parseInt(hex.slice(0, 2), 16) / 255;
      const g = parseInt(hex.slice(2, 4), 16) / 255;
      const b = parseInt(hex.slice(4, 6), 16) / 255;
      return `vec3(${r.toFixed(4)}, ${g.toFixed(4)}, ${b.toFixed(4)})`;
    }
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
  if (glslType === 'float') return formatFloat(raw ?? '0');
  if (glslType === 'int') return raw ?? '0';

  return raw ?? '0.0';
}

function formatFloat(s: string): string {
  const n = Number(s);
  if (!Number.isFinite(n)) return '0.0';
  const str = String(n);
  return str.includes('.') ? str : str + '.0';
}
