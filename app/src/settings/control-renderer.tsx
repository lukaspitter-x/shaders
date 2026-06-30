import { memo } from 'react';
import type { Control } from './schema';
import { SliderControl } from './controls/slider-control';
import { NumberControl } from './controls/number-control';
import { TextControl } from './controls/text-control';
import { SwitchControl } from './controls/switch-control';
import { SelectControl } from './controls/select-control';
import { ColorControl } from './controls/color-control';
import { Vec3Control, type Vec3 } from './controls/vec3-control';

/** Render a single declarative control against the current settings object. */
function ControlRendererImpl<S>({
  control,
  value,
  defaultValue,
  onChange,
}: {
  control: Control<S>;
  value: S;
  /** The default for this key; clicking the label resets to it. */
  defaultValue: S[keyof S];
  onChange: <K extends keyof S>(key: K, value: S[K]) => void;
}) {
  const v = value[control.key];
  const set = (next: unknown) => onChange(control.key, next as S[keyof S]);
  const onReset = () => onChange(control.key, defaultValue as S[keyof S]);

  switch (control.kind) {
    case 'slider':
      return (
        <SliderControl
          label={control.label}
          hint={control.hint}
          value={v as number}
          min={control.min}
          max={control.max}
          step={control.step}
          unit={control.unit}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'number':
      return (
        <NumberControl
          label={control.label}
          hint={control.hint}
          value={v as number}
          min={control.min}
          max={control.max}
          step={control.step}
          unit={control.unit}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'text':
      return (
        <TextControl
          label={control.label}
          hint={control.hint}
          value={v as string}
          placeholder={control.placeholder}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'switch':
      return (
        <SwitchControl
          label={control.label}
          hint={control.hint}
          value={v as boolean}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'select':
      return (
        <SelectControl
          label={control.label}
          hint={control.hint}
          value={v as string}
          options={control.options}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'color':
      return (
        <ColorControl
          label={control.label}
          hint={control.hint}
          value={v as string}
          onChange={set}
          onReset={onReset}
        />
      );
    case 'vec3':
      return (
        <Vec3Control
          label={control.label}
          hint={control.hint}
          value={v as Vec3}
          min={control.min}
          max={control.max}
          step={control.step}
          unit={control.unit}
          onChange={set}
          onReset={onReset}
        />
      );
  }
}

/**
 * Memoized so that during timeline playback — when the panel is fed a frozen
 * settings object (stable `value` ref) and a stable `onChange` — the controls
 * skip re-rendering even though their parent re-renders every frame.
 */
export const ControlRenderer = memo(ControlRendererImpl) as unknown as typeof ControlRendererImpl;
