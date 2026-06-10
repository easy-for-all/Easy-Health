"use client";

import "./workout-ui.css";

type WorkoutRowProps = {
  badge: string;
  name: string;
  sub?: string;
  tags?: string[];
  favorited?: boolean;
  isRest?: boolean;
  onFavorite?: () => void;
  onRename?: () => void;
  onClick?: () => void;
};

export function WorkoutRow({
  badge,
  name,
  sub,
  tags = [],
  favorited = false,
  isRest = false,
  onFavorite,
  onRename,
  onClick,
}: WorkoutRowProps) {
  return (
    <div className="workout-row" role="button" tabIndex={0} onClick={onClick} onKeyDown={(e) => e.key === "Enter" && onClick?.()}>
      <div className={`wr-badge ${isRest ? "rest" : ""}`}>{badge}</div>
      <div className="wr-info">
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <b>{name}</b>
          {onRename && (
            <button
              onClick={(e) => { e.stopPropagation(); onRename(); }}
              aria-label="Renomear treino"
              style={{
                background: "none", border: "none", padding: "2px 4px",
                cursor: "pointer", color: "var(--text-dim)", lineHeight: 1,
                flexShrink: 0,
              }}
            >
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ width: 13, height: 13 }}>
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
              </svg>
            </button>
          )}
        </div>
        {sub && <div className="wr-sub">{sub}</div>}
        {tags.length > 0 && (
          <div className="wr-tags">
            {tags.map((t) => (
              <span key={t} className="tag-chip muscle">{t}</span>
            ))}
          </div>
        )}
      </div>
      {onFavorite && (
        <button
          className={`wr-fav ${favorited ? "on" : ""}`}
          onClick={(e) => { e.stopPropagation(); onFavorite(); }}
          aria-label={favorited ? "Remover dos favoritos" : "Adicionar aos favoritos"}
        >
          <svg viewBox="0 0 24 24">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
          </svg>
        </button>
      )}
      <span className="wr-chev" aria-hidden>
        <svg viewBox="0 0 24 24">
          <polyline points="9 18 15 12 9 6" />
        </svg>
      </span>
    </div>
  );
}
