/**
 * Lint authored GLSL to Pencil's GLSL ES 1.00 envelope.
 *
 * The preview compiles in WebGL2, a strict *superset* of what Pencil accepts —
 * so a shader can render here and still fail on paste. This pure linter closes
 * that gap: each rule maps to a tested Pencil rejection (docs/pencil-compat.md
 * §7). Errors are hard Pencil failures; warnings are miscompiles / footguns.
 *
 * Pure (string in, findings out) so it's unit-tested and runs on every keystroke.
 */
export interface LintFinding {
  severity: 'error' | 'warning';
  rule: string;
  message: string;
  line: number;
  suggestion?: string;
}

/** Replace comments with spaces, preserving newlines so line numbers hold. */
function stripComments(src: string): string {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') {
        out += ' ';
        i++;
      }
    } else if (c === '/' && d === '*') {
      out += '  ';
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i++;
      }
      if (i < n) {
        out += '  ';
        i += 2;
      }
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

/** 1-based line number of a character offset within `text`. */
function lineAt(text: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index && i < text.length; i++) if (text[i] === '\n') line++;
  return line;
}

export function lintPencil(source: string): LintFinding[] {
  const findings: LintFinding[] = [];
  const code = stripComments(source);
  const lines = code.split('\n');

  // Names that count as compile-time constants for loop bounds.
  const constNames = new Set<string>();
  for (const m of code.matchAll(/\bconst\s+\w+\s+(\w+)\s*=/g)) constNames.add(m[1]);
  for (const m of code.matchAll(/#define\s+(\w+)\b/g)) constNames.add(m[1]);

  const bitwiseOps: { re: RegExp; name: string }[] = [
    { re: /<<|>>/, name: 'bit shift (<<, >>)' },
    { re: /\^/, name: 'bitwise xor (^)' },
    { re: /~/, name: 'bitwise not (~)' },
    { re: /(?<!&)&(?!&)/, name: 'bitwise and (&)' },
    { re: /(?<!\|)\|(?!\|)/, name: 'bitwise or (|)' },
    { re: /%/, name: 'integer modulo (%)' },
  ];

  lines.forEach((raw, idx) => {
    const line = idx + 1;

    if (/\bdiscard\b/.test(raw)) {
      findings.push({
        severity: 'error',
        rule: 'no-discard',
        message: '`discard` is rejected by Pencil.',
        line,
        suggestion: 'Mask with `gl_FragColor = vec4(0.0); return;` instead.',
      });
    }

    if (/^\s*#version\b/.test(raw)) {
      findings.push({
        severity: 'error',
        rule: 'no-version',
        message: 'Do not declare `#version` — Pencil injects it.',
        line,
      });
    }
    if (/^\s*out\b/.test(raw)) {
      findings.push({
        severity: 'error',
        rule: 'no-out',
        message: 'No `out` declarations — write to `gl_FragColor`.',
        line,
      });
    }
    if (/^\s*precision\s+(lowp|mediump|highp)\b/.test(raw)) {
      findings.push({
        severity: 'error',
        rule: 'no-precision',
        message: 'Do not declare `precision` — Pencil injects it.',
        line,
      });
    }

    const tex = /\b(texture|texelFetch|textureLod|textureGrad)\s*\(/.exec(raw);
    if (tex) {
      findings.push({
        severity: 'error',
        rule: 'no-es3-texture',
        message: `\`${tex[1]}(\` is unavailable in Pencil — only \`texture2D\` exists.`,
        line,
        suggestion: 'Use `texture2D(sampler, uv)`.',
      });
    }

    for (const op of bitwiseOps) {
      if (op.re.test(raw)) {
        findings.push({
          severity: 'error',
          rule: 'no-bitwise',
          message: `${op.name} is not allowed by Pencil.`,
          line,
        });
      }
    }

    // Loop bound must be a literal or a known const/#define.
    for (const m of raw.matchAll(/\bfor\s*\([^;]*;([^;]*);/g)) {
      const cmp = /[<>]=?\s*([A-Za-z_]\w*|\d+(?:\.\d+)?)/.exec(m[1]);
      if (cmp) {
        const rhs = cmp[1];
        if (!/^\d/.test(rhs) && !constNames.has(rhs)) {
          findings.push({
            severity: 'error',
            rule: 'const-loop-bound',
            message: `Loop bound \`${rhs}\` must be a constant (literal, \`const int\`, or \`#define\`).`,
            line,
          });
        }
      }
    }
  });

  // Whole-source checks.
  const samplerCount = (code.match(/\buniform\s+sampler2D\b/g) ?? []).length;
  const textureSize = /\btextureSize\s*\(/.exec(code);
  if (textureSize && samplerCount >= 2) {
    findings.push({
      severity: 'warning',
      rule: 'texturesize-multisampler',
      message: '`textureSize` miscompiles in Pencil with 2+ samplers (`@sdf` counts).',
      line: lineAt(code, textureSize.index),
      suggestion: 'Pass image size/aspect as a uniform instead.',
    });
  }

  // `@sdf` lives in a comment, so detect it on the original source. Only a
  // gate on a value read from the field counts: `if (d <= 0.0) return` where
  // `d` came from `texture2D(<sdf>, ...)`. Ray-miss exits and other `< 0.0`
  // early returns in an @sdf shader are not visibility gates.
  const sdfName = /@sdf\b[\s\S]*?\*\/\s*uniform\s+sampler2D\s+(\w+)/.exec(source)?.[1];
  if (sdfName) {
    const gateRe = /(\w+)(?:\.\w+)?\s*<=?\s*0\.0*\b[\s\S]{0,120}?(?:return|vec4\s*\(\s*0)/g;
    let gate: RegExpExecArray | null = null;
    for (const m of code.matchAll(gateRe)) {
      const fromField = new RegExp(`\\b${m[1]}\\s*=\\s*[^;]*texture2D\\(\\s*${sdfName}\\b`);
      if (fromField.test(code)) {
        gate = m;
        break;
      }
    }
    if (gate) {
      findings.push({
        severity: 'warning',
        rule: 'sdf-gated-visibility',
        message: 'Visibility appears gated on `@sdf` — it is empty (.r == 0) for plain Rectangles, so the fill would vanish.',
        line: lineAt(code, gate.index),
        suggestion: 'Render the full quad by default; make shape-masking opt-in.',
      });
    }
  }

  // Unknown annotation directive. Pencil hard-rejects any `@directive` it does
  // not recognize (observed: `@section` fails to load). Directives live in doc
  // comments, so scan the ORIGINAL source (they're stripped from `code`). The
  // safe set is what genuine Pencil examples use, plus the system directives.
  const KNOWN_DIRECTIVES = new Set([
    'label',
    'default',
    'range',
    'color',
    'resolution',
    'time',
    'sdf',
    'mouse',
  ]);
  const DOC_RE = /\/\*\*([\s\S]*?)\*\//g;
  let doc: RegExpExecArray | null;
  while ((doc = DOC_RE.exec(source))) {
    const bodyStart = doc.index + 3;
    const dirRe = /@(\w+)/g;
    let dir: RegExpExecArray | null;
    while ((dir = dirRe.exec(doc[1]))) {
      if (KNOWN_DIRECTIVES.has(dir[1])) continue;
      findings.push({
        severity: 'warning',
        rule: 'unknown-directive',
        message: `@${dir[1]} is not a confirmed Pencil directive; Pencil hard-rejects unknown @directives on paste.`,
        line: lineAt(source, bodyStart + dir.index),
        suggestion:
          dir[1] === 'section'
            ? 'Use a `// SECTION: Name` line comment above the doc block — Pencil ignores line comments.'
            : 'Remove it or verify Pencil supports it before pasting.',
      });
    }
  }

  return findings.sort((a, b) => a.line - b.line);
}
