// Single-select pill row shared by every filter bar in the admin panel.
//
// Extracted from onboarding-analytics/filters-bar.tsx, where it was local: the
// Usuários section had already hand-duplicated this markup, and adding the
// period/origin filters would have made a third copy.
export function PillGroup<T extends string>({
  value, options, onChange,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map((opt) => (
        <button
          key={opt.value}
          onClick={() => onChange(opt.value)}
          className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
            value === opt.value
              ? "bg-primary-500 text-white"
              : "border border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text)]"
          }`}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}
