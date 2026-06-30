import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';

/**
 * Contains a render crash so one failing region (a broken control, a viewport
 * that throws) can't blank the whole app — the shell, switcher, and other panes
 * stay alive. Per the build kit: an error boundary around the risky surfaces.
 *
 * Note: GPU-side failures (shader compile, lost WebGL context) are NOT React
 * errors and won't trip this — those surface via the viewport's own overlay.
 *
 * Give it a `key` that changes per feature (e.g. the shader id) so switching
 * shaders remounts it and clears a stale error automatically.
 */
interface Props {
  children: ReactNode;
  label?: string;
}
interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[ErrorBoundary]', error, info.componentStack);
  }

  reset = () => this.setState({ error: null });

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    return (
      <div className="flex h-full w-full items-center justify-center p-6">
        <div className="max-w-sm text-center">
          <p className="heading mb-2">{this.props.label ?? 'Something broke'}</p>
          <pre className="mb-3 max-h-48 overflow-auto whitespace-pre-wrap rounded-md border border-destructive/40 bg-destructive/10 p-3 text-left text-[11px] leading-snug text-destructive">
            {error.message}
          </pre>
          <Button variant="outline" size="sm" onClick={this.reset}>
            Retry
          </Button>
        </div>
      </div>
    );
  }
}
