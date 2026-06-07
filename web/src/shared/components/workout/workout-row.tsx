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
  onClick,
}: WorkoutRowProps) {
  return (
    <div className="workout-row" role="button" tabIndex={0} onClick={onClick} onKeyDown={(e) => e.key === "Enter" && onClick?.()}>
      <div className={`wr-badge ${isRest ? "rest" : ""}`}>{badge}</div>
      <div className="wr-info">
        <b>{name}</b>
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
