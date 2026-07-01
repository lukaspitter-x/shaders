import { describe, expect, it } from 'vitest';
import { lintPencil } from './lint-pencil';

const rules = (src: string) => lintPencil(src).map((f) => f.rule);

describe('lintPencil', () => {
  it('passes a clean ES-1.00 shader with no findings', () => {
    const src = `
/** @resolution */
uniform vec2 u_resolution;
const int N = 8;
void main() {
  float s = 0.0;
  for (int i = 0; i < N; i++) s += float(i);
  vec2 uv = gl_FragCoord.xy / u_resolution;
  gl_FragColor = vec4(uv, s, 1.0);
}`;
    expect(lintPencil(src)).toEqual([]);
  });

  it('rejects discard', () => {
    expect(rules('void main(){ if(true) discard; }')).toContain('no-discard');
  });

  it('rejects es3 texture builtins but allows texture2D', () => {
    expect(rules('void main(){ vec4 c = texture(s, uv); }')).toContain('no-es3-texture');
    expect(rules('void main(){ vec4 c = texelFetch(s, p, 0); }')).toContain('no-es3-texture');
    expect(rules('void main(){ vec4 c = texture2D(s, uv); }')).not.toContain('no-es3-texture');
  });

  it('rejects bitwise/shift/modulo but allows logical && ||', () => {
    expect(rules('void main(){ int a = b << 1; }')).toContain('no-bitwise');
    expect(rules('void main(){ int a = b % 2; }')).toContain('no-bitwise');
    expect(rules('void main(){ int a = b & 1; }')).toContain('no-bitwise');
    expect(rules('void main(){ if (a && b || c) {} }')).not.toContain('no-bitwise');
  });

  it('rejects #version, out, and precision lines', () => {
    expect(rules('#version 300 es\nvoid main(){}')).toContain('no-version');
    expect(rules('out vec4 col;\nvoid main(){}')).toContain('no-out');
    expect(rules('precision highp float;\nvoid main(){}')).toContain('no-precision');
  });

  it('allows `out` as a function parameter qualifier', () => {
    expect(rules('float f(in vec2 p, out float w){ w = 1.0; return 0.0; }')).not.toContain('no-out');
  });

  it('rejects a non-constant (uniform) loop bound but allows const/#define', () => {
    expect(rules('uniform int count;\nvoid main(){ for(int i=0;i<count;i++){} }')).toContain(
      'const-loop-bound',
    );
    expect(rules('#define N 16\nvoid main(){ for(int i=0;i<N;i++){} }')).not.toContain(
      'const-loop-bound',
    );
    expect(rules('void main(){ for(int i=0;i<32;i++){} }')).not.toContain('const-loop-bound');
  });

  it('warns on textureSize only when 2+ samplers exist', () => {
    const one = `/** @sdf */\nuniform sampler2D u_shape;\nvoid main(){ ivec2 s = textureSize(u_shape,0); }`;
    const two = `/** @sdf */\nuniform sampler2D u_shape;\nuniform sampler2D u_img;\nvoid main(){ ivec2 s = textureSize(u_img,0); }`;
    expect(rules(one)).not.toContain('texturesize-multisampler');
    expect(rules(two)).toContain('texturesize-multisampler');
  });

  it('warns when visibility is gated on @sdf', () => {
    const src = `/** @sdf */\nuniform sampler2D u_shape;\nvoid main(){ float d = texture2D(u_shape, gl_FragCoord.xy).r; if (d <= 0.0) { gl_FragColor = vec4(0.0); return; } gl_FragColor = vec4(1.0); }`;
    expect(rules(src)).toContain('sdf-gated-visibility');
  });

  it('does not flag discard appearing only in a comment', () => {
    expect(rules('void main(){ /* no discard here */ gl_FragColor = vec4(1.0); }')).not.toContain(
      'no-discard',
    );
  });

  it('warns on an unknown annotation directive but not on known ones', () => {
    expect(rules('/** @section Grid @label X @default 1 @range 0, 2 */\nuniform float u_x;')).toContain(
      'unknown-directive',
    );
    expect(rules('/** @label X @color @default #fff */\nuniform vec3 u_c;')).not.toContain(
      'unknown-directive',
    );
    // A `// SECTION:` line comment is invisible to the directive scan.
    expect(
      rules('// SECTION: Grid\n/** @label X @default 1 @range 0, 2 */\nuniform float u_x;'),
    ).not.toContain('unknown-directive');
  });
});
