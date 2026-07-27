import { CARD_ORDER, Card, CardKey } from "./types";
import { StatusBadge } from "./status-badge";
import { MetricValue, formatDateTime, formatValue } from "./metric-cell";

// Exactly six cards, in a frozen order. CARD_ORDER is the single source of
// truth and is asserted by a test — the spec is "six", not "at least six".

function ThresholdLine({ card }: { card: Card }) {
  const threshold = formatValue(card.threshold_value, card.unit);
  const baseline = formatValue(card.reference_value, card.unit);

  if (!threshold && !baseline) return null;

  return (
    <p className="mt-1 text-xs text-[var(--text-dim)]">
      {threshold ? `limite ${threshold}` : null}
      {threshold && baseline ? " · " : null}
      {baseline ? `base ${baseline}` : null}
    </p>
  );
}

function ObservabilityCard({ card }: { card: Card }) {
  return (
    <div
      className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4"
      data-testid={`observability-card-${card.key}`}
      data-card-key={card.key}
    >
      <div className="flex items-start justify-between gap-2">
        <p className="text-sm font-semibold text-[var(--text)]">{card.title}</p>
        <StatusBadge status={card.status} />
      </div>

      <p className="mt-2 text-2xl font-bold text-primary-600" data-testid={`card-value-${card.key}`}>
        <MetricValue
          value={card.value}
          unit={card.unit}
          status={card.status}
          sampleSize={card.sample_size}
        />
      </p>

      {card.headline && card.status !== "insufficient_data" ? (
        <p className="mt-0.5 text-sm text-[var(--text-muted)]">{card.headline}</p>
      ) : null}

      {card.explanation ? (
        <p className="mt-2 text-xs leading-relaxed text-[var(--text-muted)]">{card.explanation}</p>
      ) : null}

      <ThresholdLine card={card} />

      <p className="mt-2 text-xs text-[var(--text-dim)]">
        {card.window.label ? `${card.window.label} · ` : ""}
        atualizado {formatDateTime(card.updated_at)}
      </p>

      {card.incident_ids.length > 0 ? (
        <p className="mt-1 text-xs font-medium text-[var(--text-muted)]">
          {card.incident_ids.length} incidente(s) relacionado(s)
        </p>
      ) : null}
    </div>
  );
}

export function OverviewCards({ cards }: { cards: Record<CardKey, Card> }) {
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3" data-testid="observability-cards">
      {CARD_ORDER.map((key) => {
        const card = cards?.[key];
        if (!card) return null;
        return <ObservabilityCard key={key} card={card} />;
      })}
    </div>
  );
}
