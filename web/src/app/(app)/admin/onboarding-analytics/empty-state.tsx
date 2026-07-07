export function EmptyState({ label = "Sem dados ainda" }: { label?: string }) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] px-4 py-8 text-center text-sm text-[var(--text-muted)]">
      {label}
    </div>
  );
}
