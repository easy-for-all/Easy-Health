import type { OnboardingAnalytics } from "./types";
import { EmptyState } from "./empty-state";

export function StepDropoffFunnel({ data, flow }: { data: OnboardingAnalytics["step_dropoff"]; flow: string }) {
  const flowsToShow = flow ? [flow] : Object.keys(data);
  const sections = flowsToShow
    .map((key) => ({ key, steps: data[key] ?? [] }))
    .filter((section) => section.steps.some((step) => step.arrived > 0));

  if (sections.length === 0) return <EmptyState />;

  return (
    <div className="space-y-5">
      {sections.map((section) => (
        <div key={section.key} className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4">
          <p className="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">{section.key}</p>
          <div className="space-y-2">
            {section.steps.map((step) => (
              <div key={step.step_name} className="flex items-center gap-3">
                <div className="w-32 shrink-0 truncate text-xs text-[var(--text-muted)]">{step.label}</div>
                <div className="h-2 flex-1 overflow-hidden rounded-full bg-[var(--border)]">
                  <div
                    className="h-full rounded-full bg-primary-500"
                    style={{ width: `${Math.max(step.cumulative_pct, 2)}%` }}
                  />
                </div>
                <div className="w-16 shrink-0 text-right text-xs font-medium text-[var(--text)]">{step.completed}</div>
                <div className="w-20 shrink-0 text-right text-xs text-[var(--text-dim)]">
                  {step.dropoff_pct}% abandono
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
