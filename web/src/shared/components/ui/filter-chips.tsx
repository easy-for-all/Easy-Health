"use client";

interface FilterChip {
  id: string;
  label: string;
}

interface FilterChipsProps {
  chips: FilterChip[];
  active: string;
  onChange: (id: string) => void;
}

export function FilterChips({ chips, active, onChange }: FilterChipsProps) {
  return (
    <div
      style={{
        display: "flex",
        gap: 8,
        overflowX: "auto",
        padding: "2px 0",
        scrollbarWidth: "none",
        WebkitOverflowScrolling: "touch",
      }}
      role="group"
      aria-label="Filtros"
    >
      {chips.map((chip) => {
        const isActive = chip.id === active;
        return (
          <button
            key={chip.id}
            onClick={() => onChange(chip.id)}
            aria-pressed={isActive}
            style={{
              flexShrink: 0,
              padding: "6px 14px",
              borderRadius: "var(--r-pill)",
              fontSize: 13,
              fontWeight: 600,
              border: `1.5px solid ${isActive ? "var(--primary)" : "var(--border)"}`,
              background: isActive ? "var(--primary-soft)" : "transparent",
              color: isActive ? "var(--primary)" : "var(--text-muted)",
              cursor: "pointer",
              transition: "background .18s, color .18s, border-color .18s",
              whiteSpace: "nowrap",
              minHeight: 44,
            }}
          >
            {chip.label}
          </button>
        );
      })}
    </div>
  );
}
