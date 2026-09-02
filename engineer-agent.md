# Engineer Agent — Lukas's Default Build Kit

> **Read me before planning or building any tool for Lukas.** This is a *portable* blueprint — the stack, conventions, UX/visual defaults, and architectural patterns Lukas favours, stripped of any single project's specifics so they can seed a brand-new repo. Flip (this repo) is the reference implementation each rule points back to. When you start a new project for Lukas, copy this file in and let it carry the kit forward.
>
> **This file is self-maintaining.** It exists to make *you* — the engineer agent — a little better with every project. When a session teaches a *transferable* engineering lesson, record it in the logs at the bottom **in the same turn**. The litmus: **"Would this help on a *different* project?"** If yes → here. If it's only true for the project you're in → it belongs in that project's `CLAUDE.md`, not here.
>
> **Public-safety:** wherever this file is committed it inherits that repo's visibility (in Flip it goes public, history included). Never write a client name, private business detail, credential, or unreleased-work specific into it. Generic engineering taste only.

---

## ⚡ Bootstrap — first time you see this file in a repo

**If you are an agent and you've just been pointed at this file in a repo that isn't already wired to it, install yourself now, in this turn, before doing anything else:**

1. **Detect.** Check whether this repo's `CLAUDE.md` (or `AGENTS.md`, or the project's root agent-instructions file — whichever exists) already references `engineer-agent.md`. If it does, you're already installed — skip to "adopt".
2. **Wire the pointer.** If not, add **two** lines to that file (create a minimal `CLAUDE.md` if none exists):
   - near the top: `> **Portable engineering blueprint (Lukas's default kit, self-maintaining): [\`engineer-agent.md\`](engineer-agent.md)** — read it before planning or building.`
   - in its "Maintaining this file" / docs-upkeep section (or a new one): a line routing *cross-project* engineering lessons to `engineer-agent.md` and *project-specific* ones to the local file.
3. **Localize public-safety.** Determine this repo's visibility (public remote? private? ask if unsure). Update the public-safety note above to match — if private, you may record more freely; if public, the no-private-specifics litmus is hard.
4. **Adopt.** Treat everything below as your default kit for this repo. Where the repo already has a stack, *reconcile*: note in the Decisions log any place this repo deliberately deviates and why. Don't force three.js/R3F/etc. onto a project that doesn't need them — the **patterns** (schema-driven controls, feature-agnostic families, pure tested cores, sanitize-on-read, two-lane persistence, imperative perf loops) are the portable part; the exact libraries are defaults, not mandates.
5. **Confirm.** Tell the user in one line what you wired up and any deviations you noted. Then continue with their actual request.

> This block makes the file **self-installing**: copy it into any repo, tell Claude to look at it, and it plugs itself in. After step 2 it won't re-run the wiring (the pointer is the install marker).

---

## The charter — what this engineer does

Plan → build → run a repo as a self-contained craftsperson. The job is not "write the feature"; it's **grow a tool around the work**, keep it correct and fast, and leave the next session faster than this one.

- **Plan** before non-trivial work: write `step → verify: check` lines. Surface multiple interpretations instead of silently picking one. Name the simpler approach when it exists; push back when warranted. Define what "done" looks like up front.
- **Build** to match the surrounding code — its idiom, naming, comment density. New behaviour: test first, then make it pass. Bugs: a failing test that reproduces, then make it green. Refactors: the same tests pass before and after.
- **Run** the repo: typecheck after every change set, run the tests, verify visually when there's a UI. Keep the docs (`CLAUDE.md`, `ROADMAP.md`, this file) honest in the same turn you learn something.

### The north star

**"Build a tool around your work, instead of adapting the work to the tool."** Each artifact gets a bespoke tool grown around it — its own schema, controls, surfaces — never bend the artifact to fit existing tooling. This is the principle the whole kit serves: declarative schemas, experiment-agnostic families, and an agent that both extends and operates the tool are all this idea made concrete.

---

## The stack (and *why* each piece)

The value of carrying a stack is carrying the *reasons*, so you can tell when a new project should deviate.

- **Vite + React 18.3 + TypeScript.** Fast dev server, simple build, first-class path aliases (`@/*` → `src/*`). Stay on **React 18.3**, not 19, unless a project has a reason — the ecosystem below is verified against it.
- **3D / WebGL: `three@0.171` + `@react-three/fiber@8.18` + `@react-three/drei@9.122`, pinned.** R3F v8 + three 0.171 is a known-good combo; **do not casually bump to R3F v9 / three 0.18+** — it's a breaking, re-verify-everything move. Pin the trio together.
- **2D / canvas: `pixi.js@8.6`** when the artifact is genuinely 2D — don't reach for three to draw a rectangle.
- **UI: shadcn/ui "new-york" style, neutral flattened to true black/white.** Primitives are hand-written into `components/ui/` (the CLI is unreliable in non-interactive envs; writing the standard component is fine). Tokens live in one CSS file (`:root` = light, `.dark` = dark). **Keep `components/ui/` pure primitives — no app logic.**
- **Styling: Tailwind + a `cn()` class-merge util.** Responsive personalities via `md:` breakpoints; one element with two layouts beats two elements.
- **Persistence in dev: a Vite middleware file API**, not localStorage, for anything you want git-trackable and hand-editable (presets, fixtures). Accept that it's dev-only; reach for a real backend only when production persistence is actually on the table.
- **Tests: vitest**, run-once (`npm run test`), zero-config against the Vite `@` alias. Test the *pure cores*, not the UI.
- **Deploy (when there's a site): Cloudflare Workers + wrangler**, deployed per-env. A marketing/landing site can share the app's Vite + node_modules (one React/three tree) rather than spinning a second install.

> Default to the **latest, most capable Claude models** when building anything AI-facing.

---

## Visual & UX defaults (Lukas's taste)

- **Small, quiet chrome.** Body text ~13px. Headings are *dim, uppercase, tiny* (a low-contrast `.heading` utility) — deliberately understated, the artifact is the loud thing, not the panel.
- **True black/white, no accent colour by default.** When a state needs to read (on/off, dirty/saved), use *fill vs. dim* (`bg-primary` chip vs `text-muted-foreground`), not a colour swap — in a B/W theme a colour-only change is invisible.
- **Theme follows content, not a toggle.** Where possible derive light/dark from the canvas/background luminance so it "just works" instead of adding a manual switch.
- **Direct manipulation over forms.** Sliders scrub to an absolute position; clicking a control's *label* resets it to default. Dual-colour any guide/overlay (white + adjacent black) so it survives light *and* dark backgrounds.
- **Numeric inputs keep a focused draft string** — never reformat a fully-controlled number `<input>` on every keystroke (it fights typing: trailing `.`, briefly-below-min, cleared field all get stomped, caret jumps). Hold raw text locally while focused, sync from the prop on blur, preview only when the draft is a complete number. `type="text" inputMode="decimal"`, with Arrow stepping. Blur number inputs on wheel so scrolling a panel doesn't mutate values.
- **The panel is hide-able and responsive** — persist its open/closed state; default open on desktop, closed on mobile. Use `100dvh` so mobile browser chrome doesn't clip.
- **Editor chrome (section collapse, panel-open, last-used options) lives in `localStorage`, not in the git-tracked data.** Settings *values* are content; *which section is open* is per-browser chrome — keep them separate.

---

## Architecture patterns (the transferable core)

These are the reason the kit is worth carrying. Each is a rule, not Flip trivia.

- **Schema-driven, declarative controls.** Describe settings as a typed discriminated-union schema (`kind: slider | number | text | select | switch | vec3 | color | bezier | …`); a generic renderer turns the schema into UI. New control type = extend the union + add one renderer case + one pure control component. Controls are pure (`value` + `onChange`) and **never know about a specific feature**. This is what lets generic systems (animation, export, an agent) operate *any* setting from its `kind` alone, with zero per-feature code.
- **Feature-agnostic families, with the specific thing injected at the seam.** Cross-cutting systems (the settings panel, the timeline, perf, export, the agent surface) must **never import a specific feature module**. Where a family needs the registry, the shell *injects* a lookup (a `resolve…` prop / a `register…` call) so the family stays type-only on the registry. Keep "families never import features" greppable — it's what keeps the codebase composable.
- **Pure, tested cores; impure shells around them.** The risky correctness surfaces — interpolation engines, physics, history/undo, serialization, validation — are **framework-free pure modules with vitest tests**. React/three/DOM live in thin shells that call them. If logic is worth testing, it's worth extracting to a pure module first.
- **Sanitize persisted data on *read*, never trust it.** The settings schema doubles as the validator: on load, clamp numbers to range, force selects to valid options, normalize colours, drop unknown keys, prune orphaned references — with `console.warn`s. **Read-side and non-destructive by design**, so a validator bug can never corrupt stored data. Pair it with a **drift guard test** (committed presets must sanitize clean against the current schema) so a renamed/removed key fails CI loudly.
- **Forward-compatible data: merge `{...defaults, ...stored}` on read.** Adding a new setting key needs no migration — old saves get the default. Renaming/removing a key cleans the stored data in the *same* change (the drift guard enforces it). Avoid a migration framework until a project genuinely needs one.
- **Two-lane, commit-gated persistence.** Auto-save (debounced + unload-flush) writes a **gitignored working copy**; the **git-tracked "gold"** moves *only* on an explicit "Save" action. Load prefers the working copy, falls back to gold. A `dirty` flag (cheap: seeded once by a pure equality check, then flag-only) drives the save UI. This stops a stale tab or a stray edit from silently clobbering the canonical data.
- **Undo/redo as a pure, tested history module.** Record deep-cloned content snapshots at the *one or two* mutation hooks every edit funnels through (not at session-management ops). Coalesce rapid gestures by a per-mutator token within a short window so one drag = one undo step. The stack is pure + unit-tested; the store supplies the clones and applies restores.
- **Lazy-load heavy renderers.** `lazy(() => import('./HeavyViewport'))` behind Suspense so the heavy bundle (three, shaders) loads only when mounted; keep the shell light. Site/landing code that drags three into the eager bundle is a regression — keep it lazy and guard the import boundary.
- **Perf-sensitive loops: a singleton rAF that never `setState`.** Anything measuring or driving frames (FPS monitors, signal drivers, playback clocks) must read/write imperatively (refs, `textContent`, direct canvas draws) — a `setState` per frame re-renders the app every frame, *causing* the jank you're measuring. The loop runs only while it's needed (zero cost when off).
- **Override layers beat write-through for live/animated state.** Compute an `effective` value at render time and feed it to the view; never `setState` per frame into the store (it spams autosave and fights the source of truth). Freeze the editing panel while a driver is active so 60+ controls don't churn at 60fps; `memo` the renderer so stable props let it skip frames.
- **An error boundary around the risky viewport** so a crashing feature can't take down the shell (switcher, settings, save UI stay alive with a retry). Note: GPU-side failures (shader compile, lost context) are *not* React errors and still need their own guards.
- **An agent/tool surface that drives the live app, not the files.** When you expose the tool to an agent (MCP or similar), route every tool through the *live in-memory store* (so undo/autosave/dirty all apply), validate writes through the *same* sanitizer the read path uses (one validator, can't drift), and land each call as one undo step. Deterministic capture = commit state with `flushSync`, then advance the renderer manually (no rAF) so it works headless/backgrounded.

---

## Workflow & commands (the running rhythm)

- **Typecheck after every change set** — it's fast and catches most mistakes before a human sees them.
- **`npm run test`** the pure cores; add a test for any new pure logic in the same change.
- **`npm run build`** to catch build-only issues before declaring done.
- **Verify UI visually** (drive a browser) — but know the traps: a backgrounded tab pauses rAF/WebGL (canvas stuck at 300×150, screenshots blank) — that's not a code bug; foreground it. Prefer reading state via `console.log`/DOM assertions over screenshotting when the logic, not the pixels, is what you're checking.
- **Clean up after edits**: remove imports/variables/functions your change orphaned. Don't delete *pre-existing* dead code unless asked — mention it instead.
- **Keep the docs honest in the same turn**: a gotcha that cost real time → a one-line Lessons entry; a non-obvious choice → a dated Decisions entry; here if cross-project, in the project's `CLAUDE.md` if project-specific.

---

## How to extend this kit

When a new project starts, copy this file in, then *adapt*: keep the patterns, swap the specifics the new artifact demands (its schema, its renderer, its families). The kit is the skeleton; the artifact grows the muscle. If a rule here fights the new work, that's a signal — either the rule needs a caveat (record it) or the project is genuinely different (note the deviation and why).

---

## Decisions log (cross-project, dated)

> Durable engineering choices that should outlive any one project — the choice **and** the tradeoff that justified it. Edit an existing line over adding a near-duplicate; delete what proves wrong.

- **2026-06-15 — `engineer-agent.md` created as a portable, self-maintaining build-kit blueprint, committed in-repo (not global).** Captures Lukas's default stack/conventions/patterns stripped of project specifics, with Flip as the worked example; travels to new projects by being copied in. Chose committed-in-repo over a global `~/.claude` file (user's call) — it ships with the repo and is a public artifact of the open-source story; the public-safety litmus (no private specifics) is the cost of that choice. Distinct from `CLAUDE.md`'s project-specific Decisions log: this one accrues only *transferable* lessons.

---

## Lessons log (cross-project gotcha → rule)

> Gotchas general enough to recur on *any* project. Project-specific gotchas stay in that project's `CLAUDE.md`.

- **A fully-controlled number `<input>` that reformats per keystroke fights typing.** → Hold a focused draft string locally, sync from the prop on blur, preview only on a complete number; `type="text" inputMode="decimal"`. (See Visual & UX defaults.)
- **A `setState` inside a per-frame loop re-renders the whole app every frame — it *is* the jank.** → Perf-sensitive loops read/write imperatively (refs/`textContent`/canvas), never React state.
- **A backgrounded browser tab pauses rAF/WebGL** (canvas stuck at 300×150, screenshots blank, no error). → Not a code bug; foreground before sampling, or capture by manually advancing the renderer (no rAF).
- **Persisted data is never trustworthy** — validate/clamp on *read* (non-destructive), and guard committed fixtures with a drift test so a schema rename fails loudly instead of silently corrupting.
- **Switching the schema source desyncs schema from values for one render.** When the active feature changes (experiment/shader/preset), the new schema renders immediately but the `values` state usually resets via an effect — so a brand-new control reads an `undefined` key and a value-parser (e.g. a hex/number normalizer) throws, taking down the whole panel. → Feed controls `{...defaults, ...values}` so missing keys backfill, make value-parsers tolerate non-strings/undefined, and wrap the risky subtree in an error boundary so one control can't blank the app.
- **A Radix/shadcn Dialog opened from a DropdownMenu can "freeze" the app.** Both modal layers toggle `pointer-events: none` on `<body>`; their teardown race can leave it stuck after the dialog closes — rendering continues but every click is ignored, which reads as a freeze. → Put `modal={false}` on any menu whose items open dialogs, so only the Dialog manages the body lock. Diagnose in seconds: `document.body.style.pointerEvents` in the console.
- **A browser-automation tab that "hangs" on a GPU-heavy page may just be software-rendering it.** A shader fine on the real GPU can take seconds per frame under SwiftShader, so every automation call times out and it reads as a compile hang. → Before blaming the code, benchmark the GPU work in a standalone harness on real hardware (headless Chromium with the native ANGLE backend), timing compile / link / first draw / steady frame separately; read frames back as images instead of screenshotting the tab.
