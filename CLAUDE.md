# Shaders — project guide for Claude

> **Portable engineering blueprint (Lukas's default kit, self-maintaining): [`engineer-agent.md`](engineer-agent.md)** — read it before planning or building.

A GLSL shader **workbench** for authoring shaders that drop straight into
**Pencil** (and Figma custom shaders). Reuses the architecture concept from
`flip`: a self-contained "experiment" declares its adjustable parameters and a
generic UI shell auto-generates the control panel.

- **What/why + full plan:** [`docs/plan.md`](docs/plan.md)
- **Design decisions + the decoded Pencil shader contract:** [`docs/decisions.md`](docs/decisions.md)

## The one idea that shapes the codebase

The schema is **not** a hand-written TS object (as in `flip`). It lives *inside
the `.glsl` file* as Pencil's JSDoc-style uniform annotations
(`@label @default @range @color @resolution @time @sdf`). We parse those to build
the panel, so **our panel matches Pencil's by construction** and the same file
pastes straight into Pencil. The annotated `.glsl` is shader + schema in one.

## Pencil GLSL restrictions — MANDATORY when writing or editing `.glsl` files

Pencil compiles **GLSL ES 1.00** and transpiles to Metal/WGSL. Our preview is
WebGL2, which is *more permissive*. A shader that previews fine can break on
paste. **Every `.glsl` file in this project must obey these rules:**

1. **No `discard`** — use `gl_FragColor = vec4(0.0); return;` instead.
2. **No dynamic loop bounds** — loop index must compare against a `const int`.
3. **No bitwise operators** (`^ & | << >> ~`) and **no integer `%`**.
4. **No `texture()`, `texelFetch()`, `textureLod()`, `textureGrad()`** — only `texture2D` is allowed.
5. **No `#version`, `out` declarations, or `precision` lines** — Pencil injects these.
6. **No `textureSize` when ≥2 samplers exist** (including `@sdf`) — pass aspect/size as a uniform instead.
7. **Don't gate visibility on `@sdf`** — `.r == 0` for Rectangles. Default to full-quad; shape-mask is opt-in.
8. **No string/text uniforms** — no such type exists.
9. **No `1.0f`** (use `1.0`); **no `saturate()`** (use `clamp(x, 0.0, 1.0)`).
10. Entry point is `void main()` writing `gl_FragColor`; coords via `gl_FragCoord.xy / u_resolution`.
11. Image `sampler2D` samples are **Y-flipped** (`uv.y = 1.0 - uv.y`); `@sdf` is NOT flipped.

Full rationale and test results: [`docs/pencil-compat.md`](docs/pencil-compat.md).

## Stack

Vite + React 18.3 + TypeScript + Tailwind. Radix primitives in
`components/ui/`. Preview renders with **raw WebGL2 + a Pencil compatibility
prelude** (see `docs/decisions.md` D2) — *not* Three.js.

## Layout

```
app/src/
  experiments/   # one annotated .glsl per shader + registry.ts (the seam)
  glsl/          # parse-annotations.ts (.glsl → schema), pencil-prelude.ts
  render/        # webgl-quad.ts, sdf-shapes.ts, system-uniforms.ts
  settings/      # schema-driven controls (ported from flip)
  components/ui/  # Radix primitives (ported from flip) — pure, no app logic
  App.tsx        # shell: top selector + viewport + right settings column
docs/            # plan.md, decisions.md
```

## Commands

- `cd app && npm run dev` — dev server (port 5194; flip owns 5190)
- `npm run typecheck` — after every change set
- `npm run test` — vitest; test the pure cores (the GLSL parser, SDF math)
- `npm run build` — before declaring done

## Workflow

- **Auto-commit _and push_ after each major change** — once a feature or fix is
  verified (typecheck + tests + build pass), commit **and `git push`**
  immediately rather than batching. Don't wait for the user to ask.

## Deviations from the kit (reconciled)

- **No Three.js / R3F / Pixi.** The artifact is flat Pencil fragment shaders;
  the preview is a raw WebGL2 full-screen-quad harness that mirrors Pencil's
  runtime exactly. (The kit's R3F default is for 3D artifacts — not this one.)
- **Not ported (yet):** timeline, sessions/two-lane persistence, MCP agent
  bridge, export pipeline. v1 scope is viewport + settings + selector. The kit's
  patterns for these still apply when we add them.
- **`settings-column` forked** to drop the `AnimateGutter` (timeline) coupling;
  `bezier` control dropped (it's a timeline easing editor).
- The schema is **derived from `.glsl` annotations**, not authored in TS — a
  deliberate intensification of the kit's "schema-driven controls" pattern.

## Maintaining this file

When a session teaches a lesson: **cross-project** engineering lessons go to
[`engineer-agent.md`](engineer-agent.md) (its Decisions/Lessons logs);
**project-specific** decisions, the Pencil contract, and gotchas go to
[`docs/decisions.md`](docs/decisions.md). Keep both honest in the same turn you
learn something. The litmus: "Would this help on a *different* project?" → kit;
else → `docs/decisions.md`.
