/**
 * Experiment registry. An "experiment" here is one Pencil-compatible shader:
 * a single annotated `.glsl` file plus the metadata Pencil needs to apply it
 * (its id, label, and whether it's a `fill` or an `effect`).
 *
 * The shell reads this array to populate the top selector and to drive the
 * viewport + auto-generated settings panel — it never imports a specific
 * shader module. Adding a shader = drop a folder under `experiments/` with its
 * `.glsl` + an `index.ts`, then add it here.
 *
 * The `.glsl` source is imported `?raw` and parsed for its schema at render
 * time (see `glsl/parse-annotations.ts`).
 */
import flipPlasmaSource from './flip-plasma.glsl?raw';
import gradientSource from './gradient.glsl?raw';
import imageTintSource from './image-tint.glsl?raw';
import mouseGlowSource from './mouse-glow.glsl?raw';
import softShapeSource from './soft-shape.glsl?raw';
import pixelShapeSource from './pixel-shape.glsl?raw';
import staggerGridSource from './stagger-grid.glsl?raw';
import thermalSource from './thermal.glsl?raw';
import thermal2Source from './thermal-2.glsl?raw';
import tubeSource from './tube.glsl?raw';

export interface ShaderExperiment {
  id: string;
  label: string;
  type: 'fill' | 'effect';
  /** Raw GLSL source (imported via `?raw`), in Pencil's annotated dialect. */
  source: string;
}

export const EXPERIMENTS: ShaderExperiment[] = [
  { id: 'flip-plasma', label: 'Flip Plasma', type: 'fill', source: flipPlasmaSource },
  { id: 'gradient', label: 'Gradient', type: 'fill', source: gradientSource },
  { id: 'image-tint', label: 'Image Tint', type: 'fill', source: imageTintSource },
  { id: 'mouse-glow', label: 'Mouse Glow', type: 'fill', source: mouseGlowSource },
  { id: 'soft-shape', label: 'Soft Shape', type: 'fill', source: softShapeSource },
  { id: 'stagger-grid', label: 'Stagger Grid', type: 'fill', source: staggerGridSource },
  { id: 'pixel-shape', label: 'Pixel Shape', type: 'fill', source: pixelShapeSource },
  { id: 'thermal', label: 'Thermal', type: 'fill', source: thermalSource },
  { id: 'thermal-2', label: 'Thermal 2', type: 'fill', source: thermal2Source },
  { id: 'tube', label: 'Tube', type: 'fill', source: tubeSource },
];
