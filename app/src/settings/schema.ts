/**
 * Declarative settings schema. An experiment describes its editable settings
 * as a typed list of controls; the SettingsColumn renders them and reports
 * changes back via `onChange(key, value)`. This is the single source of truth
 * that keeps the Settings family decoupled from any specific experiment.
 */

export interface ControlBase<S, K extends keyof S> {
  key: K;
  label: string;
  /** Optional group header; consecutive controls with the same section merge. */
  section?: string;
  /** Optional one-line hint shown under the control. */
  hint?: string;
  /** Hide the control unless this returns true for the current settings. */
  visibleWhen?: (settings: S) => boolean;
}

export type Control<S, K extends keyof S = keyof S> = K extends keyof S
  ?
      | (ControlBase<S, K> & {
          kind: 'slider';
          min: number;
          max: number;
          step: number;
          unit?: string;
        })
      | (ControlBase<S, K> & {
          kind: 'number';
          min?: number;
          max?: number;
          step?: number;
          unit?: string;
        })
      | (ControlBase<S, K> & { kind: 'text'; placeholder?: string })
      | (ControlBase<S, K> & { kind: 'switch' })
      | (ControlBase<S, K> & { kind: 'color' })
      | (ControlBase<S, K> & {
          kind: 'select';
          options: { value: string; label: string }[];
        })
      | (ControlBase<S, K> & {
          // Compact 3-axis control (value is a [x, y, z] tuple) on one line.
          kind: 'vec3';
          min?: number;
          max?: number;
          step?: number;
          unit?: string;
        })
      | (ControlBase<S, K> & { kind: 'image' })
      | (ControlBase<S, K> & { kind: 'bezier' })
  : never;

export type SettingsSchema<S> = Control<S>[];
