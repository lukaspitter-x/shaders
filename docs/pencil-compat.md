# Pencil GLSL — compatibility learnings for the `shaders` workbench

> **Purpose & audience:** these are the hard-won facts from probing Pencil's
> shader system (2026-06-30), written as **learnings for `~/Work/_dev/shaders`** —
> the workbench whose whole promise is "author here, paste straight into Pencil."
> Canonical copy lives in that repo at `docs/pencil-compat.md`; this file in
> `_pencil/` is the field-notes original (keep them in sync, or fold this in there).
> Source of truth: Pencil's own schema/rules (Pencil MCP `get_editor_state`),
> the shipped examples in `_pencil/02/`, and live probe testing
> (`_pencil/flip-glsl-tests/`, `_pencil/webgl2-tests/`).

---

## 0. The #1 thing for the workbench: the preview-permissiveness gap

The workbench previews with **WebGL2** (`#version 300 es` prelude, `decisions.md`
D2). **Pencil compiles a STRICT subset of that.** So a shader can render perfectly
in the preview and then **fail when pasted into Pencil** — the exact failure mode
the tool exists to prevent. WebGL2 happily accepts dynamic loops, bitwise ops,
`texture()`, `texelFetch`, `discard`, and `out vec4`; **Pencil rejects all of them**
(tested below). Therefore:

> **The workbench must LINT authored shaders to Pencil's ES-1.00 envelope** — a
> preview that compiles is NOT proof Pencil will. The lint ruleset is in §7; it's
> the bridge that makes "preview-OK ⇒ Pencil-OK" actually true.

---

## 1. The shader contract

- A shader is a **FILL type** (`type: "shader"`), pointing at a `.glsl` file. It
  renders *inside its node*. (See §5.1 — there is **no shader *effect*** type, so
  no reading the live backdrop.)
- **WebGL 1.0 fragment shader (GLSL ES 1.00).** You do **not** write `#version`
  or `precision`; Pencil injects them. Entry `void main()`, output `gl_FragColor`,
  coords via `gl_FragCoord.xy / u_resolution`.
- Under the hood Pencil **parses ES-1.00 and transpiles to a `float4` Metal/WGSL
  backend** (compile errors rename `gl_FragColor→fragColor_0`,
  `gl_FragCoord→fragCoord_0`, types shown as `float4`). That transpile is WHY the
  input grammar is hard-locked to ES 1.00 even though the renderer is modern.
- No `1.0f` (use `1.0`); no `saturate` (use `clamp(x,0.0,1.0)`).

### WebGL version verdict — strictly ES 1.00 (tested)

No WebGL 2 / GLSL ES 3.00 feature compiles. Probe results (`_pencil/webgl2-tests/`):

| ES-3.00 feature | Result | Pencil error |
|---|---|---|
| non-constant (uniform) loop bound | ❌ | "loop index must be compared with a constant expression" |
| bitwise `^ << & \| ~` + integer `%` | ❌ | "operator '…' is not allowed" |
| `texelFetch()` / `texture()` | ❌ | "unknown identifier" (only `texture2D` exists) |
| `#version 300 es` + `out vec4` | ❌ | (moot — no ES-3 feature compiled) |

`textureSize` is the **sole** ES-3.00 borrowing Pencil added. **WebGPU/WGSL is not
an option** — the fill is GLSL-only.

### Minimal working shader

```glsl
/** @resolution */
uniform vec2 u_resolution;

/** @time */
uniform float u_time;

/** @label Color @color @default #46c6c0 */
uniform vec3 u_color;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  gl_FragColor = vec4(u_color * (0.5 + 0.5 * sin(u_time + uv.x * 10.0)), 1.0);
}
```

---

## 2. Magic uniforms (auto-bound)

| Tag | Type | Bound to |
|---|---|---|
| `@resolution` | `vec2` | output size in px |
| `@time` | `float` | elapsed seconds |
| `@mouse` | `vec2` | cursor, same space as `gl_FragCoord` |
| `@sdf` | `sampler2D` | the node's **own shape** SDF (see §4) — optional |

`@resolution`/`@time` must never receive user values.

## 3. Control uniforms

`@label <text>` (always set it) · `@default <value>` (`#hex` for colors) ·
`@range <min>, <max>` (slider; numbers only) · `@min`/`@max` (split form) ·
`@color` (vec3/vec4 → color picker). The description line becomes a tooltip.
Types: `float`, `int`, `vec2/3/4`, `ivec2/3/4`, `sampler2D`. **No string/text
type** (see §5.5).

## 4. Textures

- **Image input is a plain `sampler2D`** (NOT a magic tag) whose value is an
  **image URL**. Label with `@label`. Sample with `texture2D`. **Image space is
  Y-flipped** vs `gl_FragCoord` → `uv.y = 1.0 - uv.y;`. The `@sdf` texture is
  **not** flipped.
- **`@sdf`** = node's shape: `.r` = signed distance (>0 inside, in @resolution
  units), `.gb` = gradient direction (decode `gb*2.0-1.0`; use it, don't
  differentiate `.r`).

---

## 5. The permanent limits (with workbench implications)

### 5.1 No live backdrop — and (apparently) no shader *effect* type
A shader is a *fill*; the magic-uniform set is closed; there's **no backdrop
sampler**. Confirmed: Pencil's `Effect` union is only `blur` / `background_blur` /
`shadow` — **no shader effect**. So a shader cannot read the layers beneath it.
To "refract what's below," **bind an image** (a snapshot of the design below) to a
`sampler2D`; for a live-but-blur-only look, that's Pencil's built-in
`background_blur` effect (no custom code).
→ *Workbench:* `decisions.md` D4 plans a shader-*effect* type with an input raster
— **re-verify it exists before building it**; current evidence says fills only.
Model "backdrop" as a bound-image sampler, like Pencil does.

### 5.2 `discard` is rejected
Pencil errors on `discard` ("only permitted in fragment shaders" — its transpiler
wrapper disallows it). Mask via `if (cond) { gl_FragColor = vec4(0.0); return; }`
(early `return` in `main` is fine) and/or the alpha channel.
→ *Workbench:* WebGL2 preview ALLOWS `discard` → **lint-reject it** (§7).

### 5.3 `textureSize` breaks with 2+ samplers
With more than one `sampler2D` (**`@sdf` counts**), Pencil's generated
`textureSize` dispatch shim miscompiles (`int2`/`float4` mismatch). Fine with a
single sampler. With `@sdf` + an image, **don't call `textureSize`** — pass image
aspect/size as a uniform, or sample by screen UV.
→ *Workbench:* WebGL2 handles it fine → **warn/lint** when `textureSize` appears
with ≥2 samplers.

### 5.4 `@sdf` is empty for plain Rectangle layers
A Rectangle's SDF reads `.r == 0` everywhere → `if (sd <= 0.0) return transparent;`
blanks the whole fill **with no error** ("compiles, shows nothing"). **Don't gate
visibility on `@sdf`** — render the full node by default (derive edges from the
rectangular border) and make shape-masking an opt-in toggle. Only real shape nodes
populate `@sdf`.
→ *Workbench:* the SDF shape picker (D5) should default to "no mask / full quad"
and treat shape-masking as opt-in, mirroring how a Pencil Rectangle behaves.

### 5.5 No text in shaders → no shader-driven auto-size
No string/text uniform exists for shaders. You can't type a headline into a shader
control, and a shader can't measure text. "Shape fits the text" is a **layout**
concern: put a text node in an auto-layout frame, apply the glass shader as the
frame's fill (frame sizes to text; shader fills the frame). Same split Flip uses
(text measured in JS, fed as a width).
→ *Workbench:* don't promise text-reactive shaders; if needed, render glyphs via an
SDF font-atlas image sampler and feed layout-measured metrics as uniforms.

### 5.6 Loop bounds must be constants
`const int N = 64; for (int i=0;i<N;i++)`. `break`/`continue`/`return` inside loops
are allowed. (WebGL2 preview allows dynamic bounds → lint-reject.)

### 5.7 Determinism
Per-pixel `hash(gl_FragCoord)` grain changes every frame — fine on screen; note it
for frame-exact capture.

---

## 6. Capability map — Pencil's fragment envelope is generous

Within ES 1.00, heavy per-pixel work runs fine (all confirmed in
`_pencil/flip-glsl-tests/`):

- ✅ 6-octave fbm + double domain warp
- ✅ nested loops (3×3 voronoi, F1/F2 edges)
- ✅ 256-iteration escape-time fractals, smooth coloring
- ✅ **full 3D SDF raymarcher** — 96-step march, normals, soft shadows, mouse camera
- ✅ **volumetric raymarch** — 48 × 6 light-steps × 5-octave 3D fbm
- ✅ two samplers (`@sdf` + image), multi-tap frosted blur, chromatic dispersion

So the binding constraint is **ES-1.00 grammar + single-pass**, not math complexity.
3D (raymarching) is fully viable; only imported polygon meshes are out.

---

## 7. Pencil lint ruleset for the workbench (the actionable bit)

Enforce these in the `.glsl` validator so a preview that compiles guarantees Pencil
will too. Each maps to a tested Pencil rejection:

1. **Reject `discard`** → suggest `gl_FragColor = vec4(0.0); return;` (§5.2)
2. **Reject non-constant loop bounds** — loop index must compare against a constant (§5.6)
3. **Reject bitwise `^ & | << >> ~` and integer `%`** (§1 verdict)
4. **Reject `texture(`, `texelFetch(`, `textureLod(`, `textureGrad(`** — only
   `texture2D` is allowed (§1 verdict)
5. **Reject explicit `#version`, `out` declarations, and user `precision` lines** —
   Pencil injects these; `out vec4` output fails (§1 verdict)
6. **Warn on `textureSize` when ≥2 samplers** exist (incl. `@sdf`) (§5.3)
7. **Warn if visibility is gated on `@sdf`** (heuristic: `discard`/early-return on
   `u_shape.r <= 0`) — empty for rectangles (§5.4)
8. **Reject string/text uniforms** (no such type) (§5.5)
9. **No backdrop sampler** — only `@sdf` + image-URL samplers are real inputs (§5.1)

A nice property: the workbench could keep previewing in permissive WebGL2 but run
these lints on save/paste, so authors get Pencil-faithful guarantees without a
second compiler.

---

## 8. Recipe: glass that refracts the design below it

The `flip-liquid-glass.glsl` pattern (in `_pencil/flip-glsl-tests/`):

1. Glass shader is the **fill** of a top panel/shape.
2. **Bind a snapshot/export of the layers below** to an image sampler; toggle it on.
   (Empty = a procedural fallback so it still reads as glass.)
3. Derive an **edge factor** from the rectangle border (or `@sdf` when shape-masking
   is on) and bend the sample toward the edge — refraction strongest at the rim.
4. Multi-tap for **frost**; offset R/G/B along the edge normal for **dispersion**;
   add a **rim** highlight; tint slightly. Optional `@mouse` lens bulge.

Because Pencil can't read the live backdrop, re-export the snapshot when the design
beneath changes.

## 9. Pre-paste checklist

- [ ] `void main()`, writes `gl_FragColor`; no `#version`/`precision`/`out`.
- [ ] Every control uniform has `@label` (+ `@range`/`@color`/`@default`).
- [ ] No `discard`, no dynamic loops, no bitwise/int-`%`, no `texture()`/`texelFetch`.
- [ ] No `textureSize` if 2+ samplers (incl. `@sdf`).
- [ ] Visibility not gated on `@sdf` for rectangle layers.
- [ ] Image samples flip Y; `@sdf` does not.
