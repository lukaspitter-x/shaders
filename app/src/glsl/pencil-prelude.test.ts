import { describe, expect, it } from 'vitest';
import { PENCIL_FRAGMENT_PRELUDE, PENCIL_FRAGMENT_SUFFIX, wrapPencilFragment } from './pencil-prelude';

describe('pencil prelude layer space', () => {
  it('redirects gl_FragCoord in user code to the layer-relative coordinate', () => {
    const wrapped = wrapPencilFragment('void main(){ gl_FragColor = vec4(gl_FragCoord.xy, 0.0, 1.0); }');
    const userStart = wrapped.indexOf('void main(){');
    const macro = wrapped.indexOf('#define gl_FragCoord _pencilFragCoord');
    const undef = wrapped.indexOf('#undef gl_FragCoord');
    expect(macro).toBeGreaterThan(-1);
    expect(macro).toBeLessThan(userStart);
    expect(undef).toBeGreaterThan(userStart);
    // The wrapper's own main uses the real gl_FragCoord for the clip and the offset.
    expect(PENCIL_FRAGMENT_SUFFIX).toContain('_pencilFragCoord = vec4(gl_FragCoord.xy - _pencilOrigin, gl_FragCoord.zw);');
    expect(PENCIL_FRAGMENT_SUFFIX).toContain('gl_FragCoord.xy / _pencilClipRes');
    expect(PENCIL_FRAGMENT_PRELUDE).toContain('uniform vec2 _pencilOrigin;');
  });
});
