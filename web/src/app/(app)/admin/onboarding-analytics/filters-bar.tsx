import type { FlowFilter, PeriodFilter, StatusFilter } from "./types";

const PERIOD_OPTIONS: { value: PeriodFilter; label: string }[] = [
  { value: "today", label: "Hoje" },
  { value: "7d", label: "7 dias" },
  { value: "30d", label: "30 dias" },
  { value: "", label: "Desde sempre" },
];

const FLOW_OPTIONS: { value: FlowFilter; label: string }[] = [
  { value: "", label: "Todos" },
  { value: "quick", label: "Rápido" },
  { value: "complete", label: "Completo" },
  { value: "photo_ai", label: "Foto IA" },
  { value: "chat_ai", label: "Conversar com IA" },
];

const STATUS_OPTIONS: { value: StatusFilter; label: string }[] = [
  { value: "", label: "Todos" },
  { value: "trial_active", label: "Trial ativo" },
  { value: "trial_expired", label: "Trial expirado" },
  { value: "premium", label: "Premium" },
];

function PillGroup<T extends string>({
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

export function FiltersBar({
  period, flow, status, onPeriodChange, onFlowChange, onStatusChange,
}: {
  period: PeriodFilter;
  flow: FlowFilter;
  status: StatusFilter;
  onPeriodChange: (value: PeriodFilter) => void;
  onFlowChange: (value: FlowFilter) => void;
  onStatusChange: (value: StatusFilter) => void;
}) {
  return (
    <div className="mb-4 flex flex-col gap-2.5">
      <PillGroup value={period} options={PERIOD_OPTIONS} onChange={onPeriodChange} />
      <PillGroup value={flow} options={FLOW_OPTIONS} onChange={onFlowChange} />
      <PillGroup value={status} options={STATUS_OPTIONS} onChange={onStatusChange} />
    </div>
  );
}
