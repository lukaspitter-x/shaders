# Shaders — Plan

A GLSL shader workbench for authoring shaders that drop directly into **Pencil**
(and Figma custom shaders). Reuses the architecture concept from `flip`: a
self-contained **experiment** declares its adjustable parameters as typed data,
and a generic **UI shell auto-generates the control panel** from that
declaration. Claude builds the shader; you play it with sliders at 60fps.

> **The key insight that shapes everything:** in `flip`, an experiment hand-writes
> a separate TypeScript `SettingsSchema`. In Pencil, the schema lives *inside the
> `.glsl` file itself* as JSDoc-style annotations on `uniform` declarations. So
> here, **the annotated `.glsl` file is simultaneously the shader AND the schema.**
> We parse the annotations to build the panel — which means our panel matches
> Pencil's panel exactly, by construction. One source of truth, zero drift, and
> the same file pastes straight into Pencil.

---

## The Pencil shader contract (decoded from a real example)

Sources of truth: `/Users/lukas/Work/_pencil/02/soft-shape.glsl` (shape-aware
fill) and `/Users/lukas/Work/_pencil/02/aurora-background.glsl` (generative,
animated fill).

### GLSL dialect — strictly ES 1.00 (with one ES-3 borrowing)

Pencil parses **GLSL ES 1.00** and transpiles to a `float4` Metal/WGSL backend.
The authoring grammar is hard-locked to ES 1.00: no `#version`, no `precision`,
no `out`, no `discard`, no bitwise/int-`%`, no dynamic loop bounds, no
`texture()`/`texelFetch()`. The **sole** ES-3.00 borrowing is `textureSize`
(and it miscompiles with 2+ samplers — see `pencil-compat.md` §5.3). Entry
point: `void main()` writing `gl_FragColor`; coords via
`gl_FragCoord.xy / u_resolution`.

Our preview renders with **raw WebGL2 + a Pencil compatibility prelude** (see
`decisions.md` D2):

```glsl
#version 300 es
precision highp float;
out vec4 fragColor;
#define gl_FragColor fragColor
#define texture2D    texture
```

This means the preview is **more permissive** than Pencil — WebGL2 happily
compiles ES-3 features Pencil rejects. So a preview that compiles is NOT proof
Pencil will accept the shader. The workbench must **lint to Pencil's ES-1.00
envelope** (Phase 3) to close this gap.

Three.js was rejected because it injects its own prelude (`projectionMatrix`,
its own `uv` varying, auto precision) that Pencil doesn't provide.

### Uniforms are the schema (annotation-driven)

Pencil drives its control panel from annotations on `uniform` declarations:

| Annotation                         | GLSL type   | Role                                                            |
| ---------------------------------- | ----------- | -------------------------------------------------------------- |
| `/** @resolution */`               | `vec2`      | **System** — canvas size in px. No UI control.                 |
| `/** @time */`                     | `float`     | **System** — elapsed seconds. No UI control. *(confirmed)*      |
| `/** @mouse */`                    | `vec2`      | **System** — cursor position, same space as `gl_FragCoord`. No control. |
| `/** @sdf */`                      | `sampler2D` | **System** — host shape's SDF. No control. *(optional; empty for Rectangles)* |
| `@label` `@default` `@range a, b`  | `float`     | **User** — slider (min `a`, max `b`, default).                 |
| `@label` `@default` `@color`       | `vec3`      | **User** — color picker (hex `@default`).                      |
| `@label` (on `sampler2D`)          | `sampler2D` | **User** — image input (URL). Sample with `texture2D`; **Y-flipped** vs `gl_FragCoord`. |

Control **kind is inferred** from the GLSL type + annotations:
- `float` + `@range` → `slider`
- `vec3` + `@color` → `color`
- `float`, no `@range` → `number`
- (to confirm by example) `bool` → `switch`; enum/`@select` → `select`

A fill **may or may not** consume the host shape: `soft-shape.glsl` declares
`@sdf` (shape-aware); `aurora-background.glsl` is fully generative with no `@sdf`.
The renderer supplies `u_shape` (the shape picker) **only when the file declares
`@sdf`**.

### Open contract questions

1. ~~**Effect type**~~ — **Resolved: doesn't exist.** Pencil's `Effect` union is
   `blur | background_blur | shadow` only — no shader effect type. Shaders are
   fills. "Backdrop" must be a bound-image `sampler2D`. (See `pencil-compat.md` §5.1.)
2. **Other control kinds** — `bool` → switch, enums/`@select`, point/`@point`,
   gradient, etc. still unconfirmed. (Figma's Plugin API lists 13 property types.)
3. **Coordinate origin** — confirm `gl_FragCoord` origin matches our preview.

*(Resolved: `@time` is `float` elapsed-seconds; `@sdf` is optional and empty for
Rectangles; `@mouse` is cursor in `gl_FragCoord` space — see the contract table,
`decisions.md`, and `pencil-compat.md`.)*

---

## What we reuse from `flip` (and what we don't)

**Port (the valuable, experiment-agnostic layer):**
- `components/ui/` — Radix-based primitives (button, slider, select, switch,
  popover, color, tooltip, scroll-area, separator, dialog).
- `settings/` — the schema-driven control system: `control-renderer`,
  `settings-column`, `controls/*`. Adapted so its schema is *produced by the
  GLSL annotation parser* instead of a hand-written TS object.
- The shell layout: **top experiment selector + center viewport + right settings
  column.**
- Tailwind + Zod + the general Vite/React/TS setup.

**Do NOT port yet (per scope — build slowly):**
- ❌ Timeline / keyframe animation
- ❌ Sessions / presets persistence
- ❌ MCP agent bridge
- ❌ Export pipeline (PNG/video)

**Replace (R3F is the wrong layer for flat Pencil shaders):**
- Three.js / R3F renderer → a small **raw WebGL2 full-screen-quad harness**.

---

## Architecture

```
shaders/
  app/                                 # Vite + React + TS workbench
    src/
      experiments/
        registry.ts                    # globs experiments/* → selector list
        soft-shape/
          soft-shape.glsl              # the shader (= shader + schema)
          index.ts                     # { id, label }
      glsl/
        parse-annotations.ts           # .glsl → SettingsSchema + uniform manifest
        pencil-prelude.ts              # the ES-1.00 → WebGL2 compat shim
        pencil-lint.ts                 # lint to Pencil's ES-1.00 envelope (Phase 3)
      render/
        webgl-quad.ts                  # WebGL2 renderer: compile, bind, draw loop
        sdf-shapes.ts                  # built-in SDF generators → texture
        system-uniforms.ts             # providers: resolution / time / mouse / sdf
      settings/                        # ported from flip (schema-driven controls)
      components/ui/                   # ported from flip (Radix primitives)
      App.tsx                          # shell: top selector + viewport + right col
    vite.config.ts
    package.json
  docs/
    plan.md                            # this file
    decisions.md                       # lessons & decisions log (flip concept)
  CLAUDE.md                            # context file for Claude Code sessions
```

**Experiment model:** an "experiment" = one annotated `.glsl` file + a tiny
`index.ts` declaring its `id` and `label`. (The `type: 'fill' | 'effect'` field
is vestigial — Pencil only has shader fills; see D8/D9.) The registry globs the
folder so adding a shader requires no shell edits — drop the file in, it appears
in the top selector.

**Data flow per frame:**
1. Parser reads the selected `.glsl` → schema (user controls) + uniform manifest
   (which system uniforms it needs: `@resolution`, `@sdf`, `@time`, `@mouse`).
2. `SettingsColumn` renders the schema; user edits write a `values` object.
3. `system-uniforms` provides resolution (canvas), time (clock), mouse (cursor),
   and `u_shape` (SDF from the shape picker).
4. `webgl-quad` wraps the source in the Pencil prelude, compiles once, binds
   `values` + system uniforms by name, draws a full-screen triangle each frame.

---

## Build phases (incremental — one vertical slice first)

**Phase 0 — Scaffold & port** · *verify: app boots, empty shell renders*
- Vite + React + TS + Tailwind. Port `components/ui/` and `settings/` from flip.
- Shell layout: top selector (stub), center viewport (blank), right column (stub).
- Seed `CLAUDE.md` (context + conventions) and `docs/decisions.md`.

**Phase 1 — One shader, end to end** · *verify: `soft-shape.glsl` renders with a
rounded-rect SDF and its panel is auto-generated and live*
- `parse-annotations.ts`: `.glsl` → schema + manifest (handle `@resolution`,
  `@sdf`, `@label`, `@default`, `@range`, `@color`).
- `pencil-prelude.ts` + `webgl-quad.ts`: compile & draw with the compat shim.
- `sdf-shapes.ts`: one rounded-rect SDF → texture for `u_shape`.
- Wire schema → panel → uniforms. Show GLSL compile errors in the UI.

**Phase 2 — Inputs & motion** · *verify: shape picker switches geometry; animated
shaders run with play/pause and a stable FPS readout*
- Shape picker: rounded rect / circle / blob (built-in SDF generators).
- Time system uniform + render loop with play/pause; FPS meter (port flip `perf`).

**Phase 3 — Pencil lint + `@mouse` + image samplers** · *verify: a shader using
`discard` or dynamic loops shows lint errors; `@mouse` drives a uniform; an
image sampler loads, Y-flips, and samples correctly*
- **Pencil lint pass** — enforce the `pencil-compat.md` §7 ruleset on save/paste:
  reject `discard`, dynamic loop bounds, bitwise/int-`%`,
  `texture()`/`texelFetch()`, `#version`/`out`/`precision`; warn on `textureSize`
  with ≥2 samplers and on visibility gated by `@sdf`. Show diagnostics in the UI
  alongside compile errors. (The preview can keep rendering in permissive WebGL2;
  the lint is the Pencil-faithful guarantee layer.)
- **`@mouse` system uniform** — bind cursor position (same space as
  `gl_FragCoord`) when a shader declares `/** @mouse */`. Update from
  `pointermove` on the canvas.
- **Image `sampler2D` input** — a user-control `sampler2D` (no magic tag) whose
  value is an image URL. Bind as a texture; **flip Y** for image samples (the
  `@sdf` texture is NOT flipped). Support a "glass refraction" pattern: bound
  snapshot + edge-based distortion (see `pencil-compat.md` §8).

~~**Phase 3 (old) — Effect type**~~ — **Dropped.** Pencil has no shader effect
type (`Effect` union = `blur | background_blur | shadow`). Shaders are fills
only. "Backdrop" must be modeled as a bound-image sampler.

**Phase 4 — Pencil round-trip** · *verify: copy a workbench shader into Pencil
and confirm identical output; list/read shaders from the account library*
- Use the Figma MCP `list_shader_*` / `get_shader_*` / `importShaderById` flow.
- "Copy GLSL" affordance; ideally read library shaders back into the workbench.
- Verify that a shader passing all lints compiles and renders identically in
  Pencil (pixel-level validation).

---

## Success criteria ("done" for v1)

- Drop an annotated `.glsl` into `experiments/` → it appears in the top selector,
  its control panel auto-generates from the annotations, and it previews live.
- Shader **fills** render with `@sdf` shape picker, `@time` animation, `@mouse`
  cursor, and image `sampler2D` inputs (Y-flipped).
- Animated shaders run via a time uniform with play/pause.
- **The Pencil lint pass rejects any construct Pencil won't compile** — so a
  shader that passes lint and previews correctly is guaranteed to paste into
  Pencil and produce identical output.

## Risks / watch-items

- **Preview-permissiveness gap** — our WebGL2 preview compiles a superset of
  Pencil's ES-1.00 grammar. Without the Phase 3 lint pass, a shader can preview
  fine and break on paste. Mitigation: the lint ruleset (`pencil-compat.md` §7).
- The Pencil dialect is a custom shim, not vanilla WebGL1/2 — if our prelude
  drifts from Pencil's, the preview lies. Mitigation: validate against Pencil
  output pixel-for-pixel in Phase 4.
- `@select`/`bool`/point annotations are still unconfirmed — gated behind
  minting real examples (open questions above).
- Figma reportedly needs WebGPU for shaders in some browsers; our WebGL2 preview
  is a faithful *authoring* mirror, not a guarantee of Figma's internal renderer.
