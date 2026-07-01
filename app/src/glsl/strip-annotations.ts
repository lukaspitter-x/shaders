/**
 * Strip doc-block annotations from uniforms NOT in `visibleKeys`, so Pencil
 * won't generate controls for them. The uniform declaration stays (the shader
 * still needs it); only the `/** ... *​/` comment above it is removed.
 *
 * Also strips `// SECTION:` markers when every uniform in that section is hidden.
 */
export function stripHiddenAnnotations(source: string, visibleKeys: Set<string>): string {
  // Match an optional `// SECTION:` line + a `/** ... */` doc block + `uniform T name;`
  const RE =
    /(\/\/\s*SECTION:\s*[^\r\n]+?\s*\r?\n\s*)?(\/\*\*[\s\S]*?\*\/\s*)(uniform\s+\w+\s+(\w+)\s*;)/g;

  return source.replace(RE, (full, _sectionLine, _docBlock, uniformDecl, uniformName) => {
    if (visibleKeys.has(uniformName)) return full;
    return uniformDecl;
  });
}
