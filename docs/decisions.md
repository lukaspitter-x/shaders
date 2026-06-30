# Decisions & Lessons

Running log of design decisions and hard-won facts for the shaders workbench.
Newest first. Each entry: **what** we decided, **why**, and how to revisit it.
(Mirrors the `CLAUDE.md` + decisions concept from `flip`.)

---

## D8 — Pencil is strictly WebGL 1.0 / ES 1.00; the preview is more permissive → we must LINT to Pencil

**Tested 2026-06-30** (probe batteries in `~/Work/_pencil/{flip-glsl-tests,webgl2-tests}/`;
full write-up: [`pencil-compat.md`](pencil-compat.md)). Pencil parses **GLSL ES 1.00**
and transpiles to a `float4` Metal/WGSL backend, so the authoring grammar is
hard-locked to ES 1.00. **No WebGL 2 feature compiles** — dynamic (uniform) loop
bounds, bitwise `^ << & %`, and `texture()`/`texelFetch()` are all rejected;
`textureSize` is the *only* ES-3 borrowing. WebGPU/WGSL is not an option (GLSL-only fill).

**The risk this creates for us:** our preview is **WebGL2** (D2's `#version 300 es`
prelude), which compiles a strict *superset* of Pencil — so a shader can preview
fine and then fail on paste, defeating the whole "paste straight into Pencil"
promise. **Decision: the workbench must lint authored shaders to Pencil's ES-1.00
envelope** (preview-OK ≠ Pencil-OK). The lint ruleset (`pencil-compat.md` §7):
reject `discard`, dynamic loops, bitwise/int-`%`, `texture()/texelFetch()`,
explicit `#version`/`out`/`precision`; warn on `textureSize` with ≥2 samplers and
on visibility gated by `@sdf`.

**Other tested Pencil facts that constrain us:**
- **`discard` is rejected** ("only permitted in fragment shaders") → mask via
  `gl_FragColor = vec4(0.0); return;`.
- **`textureSize` miscompiles with 2+ samplers** (`@sdf` counts) → fine with one;
  with `@sdf` + image, pass aspect as a uniform instead.
- **`@sdf` is empty for plain Rectangle layers** (`.r == 0`) → **don't gate
  visibility on it**; default to full-quad, shape-mask opt-in. (Tightens D5's shape
  picker behavior.)
- **No live backdrop / no shader *effect* type.** Pencil's `Effect` union is only
  `blur`/`background_blur`/`shadow` — **no shader effect**. Shaders are fills; a
  "backdrop" must be a bound-image sampler, not the live layers below.
  **→ Re-verify D4's shader-effect-with-input-raster plan before building it; current
  evidence says fills only.**
- **No string/text uniform** → text-reactive shapes are a layout concern, not a
  shader one (font-atlas SDF + layout-measured metrics if ever needed).

**Revisit if:** Pencil ships WebGL 2 shaders, a shader effect type, or export-to-code.

## D9 — No shader effect type; Phase 3 pivoted to Pencil lint + @mouse + image samplers

**Confirmed 2026-06-30** (full write-up: `pencil-compat.md`). Pencil's `Effect`
union is `blur | background_blur | shadow` — **no shader effect type**. Shaders
are fills only. A "backdrop" must be a bound-image `sampler2D`, not a live layer
read.

**Roadmap impact:**
- Plan Phase 3 (effect type + input raster) → **dropped and replaced** with:
  Pencil lint pass (`pencil-compat.md` §7 ruleset), `@mouse` system uniform, and
  image `sampler2D` input support (with Y-flip). This closes the
  preview-permissiveness gap (D8) and adds the two remaining Pencil input modes.
- D4's scope narrowed from "fill AND effect" to "fills only."
- The experiment `type: 'fill' | 'effect'` field in `index.ts` is vestigial.

**Also confirmed (from the same probe session):**
- `@mouse` is a real magic uniform (`vec2`, cursor in `gl_FragCoord` space).
- Image `sampler2D` inputs are Y-flipped vs `gl_FragCoord`; `@sdf` is not.
- `@sdf` reads `.r == 0` everywhere for plain Rectangle layers → don't gate
  visibility on it; default to full-quad rendering.
- Heavy per-pixel math (6-octave fbm, 96-step raymarchers, volumetrics) runs fine
  within ES 1.00 — the binding constraint is grammar, not compute.

**Revisit if:** Pencil adds a shader effect type.

## D1 — The annotated `.glsl` file is the single source of truth (shader + schema)

**Decided:** We parse Pencil's JSDoc-style uniform annotations directly from the
`.glsl` file to auto-generate the control panel, instead of hand-writing a
separate TypeScript schema like `flip` does.
**Why:** The annotations are Pencil's *own* control format, so a panel built from
them matches Pencil's panel by construction — zero drift, one file to maintain,
and the same file pastes straight into Pencil.
**Revisit if:** Pencil changes its annotation syntax, or we need controls Pencil
can't express.

## D2 — Preview renders with raw WebGL2 + a Pencil compatibility prelude

**Decided:** The viewport is a raw WebGL2 full-screen-quad harness that wraps the
user's source in:
```glsl
#version 300 es
precision highp float;
out vec4 fragColor;
#define gl_FragColor fragColor
#define texture2D    texture
```
**Why:** Pencil shaders mix WebGL1 syntax (`gl_FragColor`, `texture2D`) with
GLSL ES 3.00 functions (`textureSize`), which compiles in neither pure dialect —
so Pencil itself uses this kind of shim. Three.js was rejected: it injects its
own prelude (`projectionMatrix`, its own `uv` varying) that Pencil doesn't
provide, so it would preview against non-existent uniforms.
**Revisit if:** Phase 1 pixel-comparison against Pencil reveals the real shim
differs — record the corrected prelude here.

## D3 — Reuse flip's UI/settings layer; drop R3F, timeline, sessions, agent, export

**Decided:** Port `flip`'s `components/ui/` (Radix primitives) and `settings/`
(schema-driven controls + `settings-column`). Do **not** port Three.js/R3F,
timeline, sessions, MCP agent bridge, or export for v1.
**Why:** The experiment-agnostic UI is flip's reusable value; the renderer and
the deferred subsystems are not needed for a flat-shader workbench starting
small (viewport + right column + top selector).
**Revisit if:** We later want animation timelines or preset persistence.

## D4 — Scope v1 to fills only, with SDF shape picker, time, and mouse

**Decided (updated 2026-06-30):** Support shader *fills* only — `@sdf` shape
picker (rounded rect / circle / blob), `@time` animation clock with play/pause,
`@mouse` cursor uniform, and image `sampler2D` inputs. ~~Shader effects~~ dropped
(see D9).
**Why:** Pencil has no shader effect type (D9). The original scope included
effects gated behind minting a real example; probing confirmed they don't exist.

## D5 — Phase 1 (one shader end-to-end) + `@sdf` support: DONE

**Built:**
- `glsl/parse-annotations.ts` — pure parser: annotated `.glsl` → settings schema
  + uniform manifest (`system` = role→name). Unit-tested (`*.test.ts`).
- `glsl/pencil-prelude.ts` — the D2 shim + a `gl_VertexID` full-screen triangle.
- `render/webgl-quad.ts` — WebGL2 renderer: compiles the wrapped shader,
  introspects active uniforms, binds `u_resolution`/`u_time`/user values by name
  (hex→rgb for vec3 colors), uploads the `@sdf` host shape as an R16F texture.
- `render/sdf-shapes.ts` — pure SDF generators (rounded-rect / circle / blob).
- `render/shader-viewport.tsx` — canvas + clock + rAF loop (no per-frame
  setState; settings read from a ref), regenerates the SDF on shape/size change.
- `App.tsx` — auto-built panel, play/pause, and a Shape picker shown only for
  `@sdf` shaders. Registered `flip-plasma.glsl` (generative) and
  `soft-shape.glsl` (shape-aware).
**Verified:** both shaders render live, sliders/colors drive uniforms in real
time, all three host shapes swap correctly, typecheck + tests green.
**Open risk (unchanged):** not yet pixel-validated against Pencil's real output;
the SDF distance scaling (below) is reasoned, not confirmed.

## D6 — Phase 2 solidified (robustness): DONE

**Built:**
- `components/error-boundary.tsx` — wraps the viewport and the settings column
  (keyed by shader id so a switch clears stale errors), so one crashing region
  can't blank the app. (GPU/compile failures aren't React errors — those stay on
  the viewport's own overlay.)
- **FPS meter** — *(superseded in D7 by flip's `FpsPanel`)* originally a dim
  corner readout written via `textContent` from the rAF loop.
- **Sanitize-on-read** — `sanitizeValues(schema, values)` clamps numeric controls
  to range before they reach the shader/panel; colors pass through (the renderer
  tolerates bad hex). Unit-tested. Wired into `effectiveValues`.
- **Compile-error overlay** — exercised with a deliberately broken shader: the
  log shows the user-source line (prelude offset remapped) and the last-good
  frame keeps rendering behind it; no crash.
**Verified:** typecheck + 7 tests green; FPS, pause, error overlay, and recovery
all confirmed in-browser.

## D9 — Shape picker: top-bar, for ALL shaders, with thumbnails + None + upload

**Decided/Built (user request):** The host-shape picker stays in the top bar but
is now a thumbnail popover (`components/shape-picker.tsx`) available for **every**
shader — because in Pencil a fill is clipped to its host layer, not just `@sdf`
ones. Options: **None (full background)** + built-ins + uploads + an upload tile.

- **Layer clip for any shader** — the prelude now wraps the user's `main`
  (`#define main _pencilUserMain` … `#undef main` + our `main`) and multiplies
  output alpha by the shape mask (`_pencilClip`/`_pencilClipRes`/`_pencilClipOn`).
  So a *generative* shader (plasma) clips to a circle/blob too, emulating Pencil's
  layer clip without touching user source. Verified: plasma clipped to a blob.
- **Per-type default** — `@sdf` (shape-aware) shaders default to a real shape;
  generative shaders default to None. None feeds a 1×1 zero SDF, so a shape-aware
  shader on None renders empty (the D8 empty-rectangle reality — flagged to user).
- **Uploads → SDF** — `render/edt.ts` (pure, exact Euclidean distance transform,
  unit-tested) + `render/image-sdf.ts` (decode → mask → EDT → normalize). Custom
  shapes are `makeCustomShape` `ShapeDef`s, **in-memory only** (no persistence).
- `ShapeDef.sample(px,py)` is the unifying abstraction (built-in analytic or
  uploaded bilinear); `generateSdf` and the thumbnails both use it.
**Verified:** picker/thumbnails/None/generative-clip/shape-aware all confirmed
in-browser; EDT unit-tested. **Not** browser-verified: the actual file upload
(the `file_upload` MCP tool dropped path support) — pipeline wired + EDT tested.

## D7 — Match flip's top-bar: FpsPanel, undo/redo, selector-on-left

**Decided/Built (user request — make these the same as flip):**
- Ported flip's `perf/fps-monitor.ts` (singleton, measures experienced page
  frame rate, no React state) + `perf/fps-panel.tsx` (Activity toggle →
  sparkline + numeric `N fps` + logging toggle). Replaced the D6 corner meter.
- Ported flip's pure `lib/history.ts` (+ its 11 tests) and wired **undo/redo over
  the `values` state**: each edit records the pre-edit snapshot coalesced by
  control key (one slider drag = one step), with ⌘Z / ⌘⇧Z shortcuts (skipped
  while a text field is focused). A props-based `UndoRedoButtons` (decoupled from
  flip's sessions store, which we don't have).
- Header layout now mirrors flip (`h-10`, gap-3): **shader selector on the left**,
  then FpsPanel, then undo/redo; shape picker + play/pause pushed right (`ml-auto`).
**Why:** Consistency with flip's instrument; undo/redo is core editing UX.
**Note:** History resets on shader switch (per-shader). No persistence yet, so
undo history is in-memory only.

---

## Confirmed contract facts (from real Pencil examples)

- **`@time`** → `float`, elapsed **seconds**. Confirmed in `aurora-background.glsl`
  (`u_time * u_speed`).
- **`@sdf`** → `sampler2D`, host shape's SDF, and is **optional**: `soft-shape`
  uses it (shape-aware fill); `aurora-background` omits it (generative fill). Only
  provide `u_shape` when the file declares `@sdf`. **Empty (`.r == 0`) for plain
  Rectangle layers** — don't gate visibility on it.
- **`@mouse`** → `vec2`, cursor position in `gl_FragCoord` space.
- **Image `sampler2D`** (no magic tag, just `@label`) → value is an image URL.
  **Y-flipped** vs `gl_FragCoord` (`uv.y = 1.0 - uv.y`); `@sdf` is NOT flipped.
- **No shader effect type** — Pencil's `Effect` union = `blur | background_blur |
  shadow`. Shaders are fills only (see D9).
- **`@resolution`** → `vec2`, canvas size in pixels.
- **`@color`** → on a `vec3`, with a hex `@default` (e.g. `#0d2b3e`).
- **`@range a, b`** → on a `float`, drives slider min/max.
- **Dialect** → **GLSL ES 1.00 only** (tested — see D8): `gl_FragCoord`,
  `gl_FragColor`, `texture2D`, constant loop bounds, no bitwise/int-`%`. The single
  ES-3.00 borrowing is `textureSize` (and it breaks with 2+ samplers). Entry point
  is `void main()` writing `gl_FragColor`; no `#version`/`precision`/`out`.
- **`@sdf` channel convention** (decoded from `soft-shape.glsl`'s marcher):
  `u_shape.r` is a **signed distance in pixels, positive inside the shape, ≤0
  outside**. It marches `t += max(r, 1.0)` in canvas-pixel units and breaks when
  `r <= 0`, and uses `textureSize(u_shape, 0)`. Our generators store interior
  distance scaled by canvas **height** in px (`render/sdf-shapes.ts`); this units
  choice is reasoned, **not yet confirmed** against a Pencil-minted SDF.

## Lessons (project gotchas)

- **Schema/values desync on source switch crashes a control.** Switching shaders
  recomputes the schema immediately, but the `values` state (reset via effect)
  lags one render — so a new control (`soft-shape`'s `u_color`) read an
  `undefined` key and `normalizeHex` threw, blanking the whole app (no error
  boundary). Fix: pass `{...defaults, ...values}` so a missing key backfills, and
  `normalizeHex` now rejects non-strings. (Also logged cross-project in
  `engineer-agent.md`.) Consider adding an error boundary around the viewport.

## Still unconfirmed (resolve by minting examples)

- ~~Effect-type input-raster annotation~~ — **Resolved: no shader effect type** (D9).
- Annotations for `bool`/switch, enums/`@select`, points, gradients.
- `gl_FragCoord` origin vs our preview, and the `@sdf` distance units.
